"""Unit tests for notification email worker core."""
from datetime import timedelta
import pytest
from sqlalchemy import select
from app.config import Settings
from app.models import Notification, Tenant, User, utcnow
from app.services.email.base import EmailMessage, EmailProvider, EmailSendError, EmailSendResult
from app.services.notification_worker import (
    claim_batch,
    process_one,
    render_email,
    TenantEmailNotificationConfig,
)


class FakeEmailProvider(EmailProvider):
    supports_idempotency: bool = True

    def __init__(self, behavior="success", error_code=None, retryable=False):
        self.behavior = behavior
        self.error_code = error_code
        self.retryable = retryable
        self.sent_calls = []

    async def send(self, message: EmailMessage, idempotency_key: str) -> EmailSendResult:
        self.sent_calls.append({"message": message, "idempotency_key": idempotency_key})
        if self.behavior == "success":
            return EmailSendResult(provider_message_id=f"fake-{len(self.sent_calls)}")
        elif self.behavior == "error":
            raise EmailSendError(
                f"Simulated error ({self.error_code})",
                retryable=self.retryable,
                code=self.error_code,
            )
        raise RuntimeError("Unknown behavior")


@pytest.fixture
async def worker_setup(db_session, test_tenant, test_user):
    # Set tenant custom email config
    test_tenant.config = {
        "notifications": {
            "email": {
                "enabled": True,
                "from_name": "Algeria Tourism Board",
                "reply_to": "contact@algeria.travel",
            }
        }
    }
    db_session.add(test_tenant)
    await db_session.commit()
    await db_session.refresh(test_tenant)
    return test_tenant, test_user


@pytest.mark.asyncio
async def test_render_email_deterministic_stored_locale(worker_setup):
    tenant, user = worker_setup
    now = utcnow()
    notif = Notification(
        tenant_id=tenant.id,
        user_id=user.id,
        type="booking_confirmed",
        payload={"poi_name": "Casbah"},
        locale="fr",
        created_at=now,
    )
    # Even if user.locale is changed to 'en', render_email must use stored notif.locale 'fr'
    user.locale = "en"
    msg = render_email(notif, user, tenant)
    assert msg.to == user.email
    assert msg.from_name == "Algeria Tourism Board"
    assert msg.reply_to == "contact@algeria.travel"
    assert msg.subject == "Réservation confirmée"
    assert "Casbah" in msg.text


@pytest.mark.asyncio
async def test_process_one_success(db_session, worker_setup):
    tenant, user = worker_setup
    now = utcnow()
    notif = Notification(
        tenant_id=tenant.id,
        user_id=user.id,
        type="booking_confirmed",
        payload={"poi_name": "Tipaza"},
        locale="fr",
        email_status="pending",
    )
    db_session.add(notif)
    await db_session.commit()

    claimed_ids = await claim_batch(db_session, now=now, limit=10)
    assert notif.id in claimed_ids

    provider = FakeEmailProvider(behavior="success")
    await process_one(db_session, notif.id, provider, now=now)

    await db_session.refresh(notif)
    assert notif.email_status == "sent"
    assert notif.email_sent_at is not None
    assert notif.provider_message_id == "fake-1"
    assert notif.locked_until is None
    assert notif.last_error is None
    assert len(provider.sent_calls) == 1
    assert provider.sent_calls[0]["idempotency_key"] == f"notification-{notif.id}"


@pytest.mark.asyncio
async def test_process_one_retryable_then_success(db_session, worker_setup):
    tenant, user = worker_setup
    now = utcnow()
    notif = Notification(
        tenant_id=tenant.id,
        user_id=user.id,
        type="booking_confirmed",
        payload={"poi_name": "Oran"},
        locale="en",
        email_status="pending",
    )
    db_session.add(notif)
    await db_session.commit()

    # Claim attempt 1
    claimed_ids = await claim_batch(db_session, now=now, limit=10)
    assert notif.id in claimed_ids

    # Provider fails with retryable error
    provider1 = FakeEmailProvider(behavior="error", retryable=True, error_code="timeout")
    await process_one(db_session, notif.id, provider1, now=now)

    await db_session.refresh(notif)
    assert notif.email_status == "pending"
    assert notif.email_attempts == 1
    assert notif.next_attempt_at == now + timedelta(minutes=1)
    assert notif.locked_until is None
    assert "timeout" in notif.last_error

    # Second attempt: advance clock past next_attempt_at
    later = now + timedelta(minutes=2)
    claimed_2 = await claim_batch(db_session, now=later, limit=10)
    assert notif.id in claimed_2

    provider2 = FakeEmailProvider(behavior="success")
    await process_one(db_session, notif.id, provider2, now=later)

    await db_session.refresh(notif)
    assert notif.email_status == "sent"
    assert notif.email_attempts == 2
    assert notif.provider_message_id == "fake-1"

    # Both provider calls must have used identical idempotency_key
    assert provider1.sent_calls[0]["idempotency_key"] == f"notification-{notif.id}"
    assert provider2.sent_calls[0]["idempotency_key"] == f"notification-{notif.id}"
    # And identical message content
    assert provider1.sent_calls[0]["message"].text == provider2.sent_calls[0]["message"].text


@pytest.mark.asyncio
async def test_process_one_non_retryable(db_session, worker_setup):
    tenant, user = worker_setup
    now = utcnow()
    notif = Notification(
        tenant_id=tenant.id,
        user_id=user.id,
        type="booking_confirmed",
        email_status="pending",
    )
    db_session.add(notif)
    await db_session.commit()

    claimed_ids = await claim_batch(db_session, now=now, limit=10)
    provider = FakeEmailProvider(behavior="error", retryable=False, error_code="invalid_email")
    await process_one(db_session, notif.id, provider, now=now)

    await db_session.refresh(notif)
    assert notif.email_status == "failed"
    assert notif.locked_until is None
    assert "invalid_email" in notif.last_error


@pytest.mark.asyncio
async def test_process_one_max_attempts_exceeded(db_session, worker_setup):
    tenant, user = worker_setup
    now = utcnow()
    notif = Notification(
        tenant_id=tenant.id,
        user_id=user.id,
        type="booking_confirmed",
        email_status="pending",
        email_attempts=4,  # Next claim makes it 5
        first_attempt_at=now - timedelta(hours=2),
    )
    db_session.add(notif)
    await db_session.commit()

    claimed_ids = await claim_batch(db_session, now=now, limit=10)
    provider = FakeEmailProvider(behavior="error", retryable=True, error_code="500")
    await process_one(db_session, notif.id, provider, now=now)

    await db_session.refresh(notif)
    assert notif.email_status == "failed"
    assert "Max attempts/age reached" in notif.last_error


@pytest.mark.asyncio
async def test_process_one_cut_off_at_24_hours(db_session, worker_setup):
    tenant, user = worker_setup
    now = utcnow()
    notif = Notification(
        tenant_id=tenant.id,
        user_id=user.id,
        type="booking_confirmed",
        email_status="pending",
        email_attempts=1,
        first_attempt_at=now - timedelta(hours=25),  # > 24h
    )
    db_session.add(notif)
    await db_session.commit()

    claimed_ids = await claim_batch(db_session, now=now, limit=10)
    provider = FakeEmailProvider(behavior="error", retryable=True, error_code="timeout")
    await process_one(db_session, notif.id, provider, now=now)

    await db_session.refresh(notif)
    assert notif.email_status == "failed"
    assert "Max attempts/age reached" in notif.last_error


@pytest.mark.asyncio
async def test_claim_batch_lease_reclaim(db_session, worker_setup):
    tenant, user = worker_setup
    now = utcnow()
    # Notification stuck in sending with expired lease
    notif = Notification(
        tenant_id=tenant.id,
        user_id=user.id,
        type="booking_confirmed",
        email_status="sending",
        email_attempts=1,
        locked_until=now - timedelta(seconds=10),
    )
    db_session.add(notif)
    await db_session.commit()

    claimed = await claim_batch(db_session, now=now, limit=10)
    assert notif.id in claimed

    await db_session.refresh(notif)
    assert notif.email_status == "sending"
    assert notif.email_attempts == 2
    assert notif.locked_until > now


@pytest.mark.asyncio
async def test_process_one_inactive_tenant_and_cross_tenant_user(db_session, worker_setup):
    tenant, user = worker_setup
    now = utcnow()

    # 1. Tenant disabled
    tenant.is_active = False
    db_session.add(tenant)
    notif1 = Notification(
        tenant_id=tenant.id,
        user_id=user.id,
        type="booking_confirmed",
        email_status="sending",
    )
    db_session.add(notif1)
    await db_session.commit()

    provider = FakeEmailProvider(behavior="success")
    await process_one(db_session, notif1.id, provider, now=now)
    await db_session.refresh(notif1)
    assert notif1.email_status == "skipped"
    assert "Tenant inactive" in notif1.last_error

    # 2. Cross tenant mismatch
    other_tenant = Tenant(
        slug="other-tenant-isolation",
        name="Other",
        default_currency="USD",
    )
    db_session.add(other_tenant)
    await db_session.flush()

    notif2 = Notification(
        tenant_id=other_tenant.id,
        user_id=user.id,  # User belongs to test_tenant, not other_tenant!
        type="booking_confirmed",
        email_status="sending",
    )
    db_session.add(notif2)
    await db_session.commit()

    await process_one(db_session, notif2.id, provider, now=now)
    await db_session.refresh(notif2)
    assert notif2.email_status == "skipped"
    assert "User missing or does not belong to notification tenant" in notif2.last_error


@pytest.mark.asyncio
async def test_concurrent_claim_batch_no_overlap(worker_setup):
    from tests.conftest import TestSessionLocal
    tenant, user = worker_setup
    now = utcnow()

    # Insert 4 notifications
    async with TestSessionLocal() as s:
        for i in range(4):
            s.add(
                Notification(
                    tenant_id=tenant.id,
                    user_id=user.id,
                    type="booking_confirmed",
                    payload={"idx": i},
                    email_status="pending",
                )
            )
        await s.commit()

    # Run two claims in separate sessions
    async with TestSessionLocal() as s1, TestSessionLocal() as s2:
        c1 = await claim_batch(s1, now=now, limit=2)
        c2 = await claim_batch(s2, now=now, limit=2)

    assert len(c1) == 2
    assert len(c2) == 2
    assert set(c1).isdisjoint(set(c2))
