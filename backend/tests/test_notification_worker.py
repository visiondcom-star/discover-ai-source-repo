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
    # Cut off before send triggers "Idempotency window exceeded before send"
    assert "Idempotency window exceeded before send" in notif.last_error
    # Provider was not called because guard stopped before send
    assert len(provider.sent_calls) == 0


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
async def test_process_one_tenant_email_disabled_skipped(db_session, worker_setup):
    """Tenant.config['notifications']['email']['enabled'] == False -> skipped."""
    tenant, user = worker_setup
    now = utcnow()
    tenant.config = {"notifications": {"email": {"enabled": False}}}
    db_session.add(tenant)
    await db_session.commit()

    notif = Notification(
        tenant_id=tenant.id,
        user_id=user.id,
        type="booking_confirmed",
        email_status="sending",
    )
    db_session.add(notif)
    await db_session.commit()

    provider = FakeEmailProvider(behavior="success")
    await process_one(db_session, notif.id, provider, now=now)

    await db_session.refresh(notif)
    assert notif.email_status == "skipped"
    assert notif.last_error == "Tenant email notifications disabled in config"
    assert len(provider.sent_calls) == 0


@pytest.mark.asyncio
async def test_claim_batch_attempts_gte_5_fails_without_send(db_session, worker_setup):
    """Ligne reprise avec email_attempts >= 5 -> failed sans envoi (FakeEmailProvider.sent_calls vide)."""
    tenant, user = worker_setup
    now = utcnow()
    notif = Notification(
        tenant_id=tenant.id,
        user_id=user.id,
        type="booking_confirmed",
        email_status="sending",
        email_attempts=5,
        locked_until=now - timedelta(seconds=10),
    )
    db_session.add(notif)
    await db_session.commit()

    claimed = await claim_batch(db_session, now=now, limit=10)
    assert notif.id not in claimed

    await db_session.refresh(notif)
    assert notif.email_status == "failed"
    assert "Max attempts (5) exceeded on lease reclaim" in notif.last_error

    provider = FakeEmailProvider(behavior="success")
    assert len(provider.sent_calls) == 0


@pytest.mark.asyncio
async def test_process_one_guard_24h_before_send(db_session, worker_setup):
    """Garde 24 h avant envoi : si email_attempts > 1 et now - first_attempt_at >= 24 h -> failed sans envoi."""
    tenant, user = worker_setup
    now = utcnow()
    notif = Notification(
        tenant_id=tenant.id,
        user_id=user.id,
        type="booking_confirmed",
        email_status="sending",
        email_attempts=2,
        first_attempt_at=now - timedelta(hours=25),
    )
    db_session.add(notif)
    await db_session.commit()

    provider = FakeEmailProvider(behavior="success")
    await process_one(db_session, notif.id, provider, now=now)

    await db_session.refresh(notif)
    assert notif.email_status == "failed"
    assert notif.last_error == "Idempotency window exceeded before send"
    assert len(provider.sent_calls) == 0


@pytest.mark.asyncio
async def test_process_one_render_exception_failed(db_session, worker_setup, monkeypatch):
    """Exception de rendu -> failed avec last_error 'Render error: <type>' sans envoi."""
    tenant, user = worker_setup
    now = utcnow()
    notif = Notification(
        tenant_id=tenant.id,
        user_id=user.id,
        type="booking_confirmed",
        email_status="sending",
        email_attempts=1,
    )
    db_session.add(notif)
    await db_session.commit()

    def mock_render_fail(*args, **kwargs):
        raise KeyError("missing_template_var")

    monkeypatch.setattr("app.services.notification_worker.render_email", mock_render_fail)

    provider = FakeEmailProvider(behavior="success")
    await process_one(db_session, notif.id, provider, now=now)

    await db_session.refresh(notif)
    assert notif.email_status == "failed"
    assert notif.last_error == "Render error: KeyError"
    assert len(provider.sent_calls) == 0


@pytest.mark.asyncio
async def test_concurrent_claim_batch_no_overlap(worker_setup):
    from tests.conftest import TestSessionLocal
    from sqlalchemy import or_, and_
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

    # s1 exécute le SELECT ... FOR UPDATE SKIP LOCKED de claim_batch SANS commit
    # pendant que s2 appelle claim_batch complet
    async with TestSessionLocal() as s1:
        stmt = (
            select(Notification)
            .where(
                or_(
                    and_(
                        Notification.email_status == "pending",
                        or_(
                            Notification.next_attempt_at.is_(None),
                            Notification.next_attempt_at <= now,
                        ),
                    ),
                    and_(
                        Notification.email_status == "sending",
                        Notification.locked_until.is_not(None),
                        Notification.locked_until <= now,
                    ),
                )
            )
            .order_by(Notification.created_at.asc())
            .limit(2)
            .with_for_update(skip_locked=True)
        )
        res1 = await s1.execute(stmt)
        rows_s1 = res1.scalars().all()
        ids_s1 = {n.id for n in rows_s1}
        assert len(ids_s1) == 2

        # Session s2 appelle claim_batch complet alors que s1 détient le verrou FOR UPDATE sans commit
        async with TestSessionLocal() as s2:
            c2 = await claim_batch(s2, now=now, limit=2)
            ids_s2 = set(c2)

        # Vérifier que les ensembles d'identifiants sont disjoints et que s2 obtient bien les autres lignes
        assert len(ids_s2) == 2
        assert ids_s1.isdisjoint(ids_s2)

        # Puis rollback de s1
        await s1.rollback()


@pytest.mark.asyncio
async def test_run_once(worker_setup):
    from tests.conftest import TestSessionLocal
    from app.services.notification_worker import run_once
    tenant, user = worker_setup
    now = utcnow()

    notif = Notification(
        tenant_id=tenant.id,
        user_id=user.id,
        type="booking_confirmed",
        payload={"poi_name": "Ghardaia"},
        locale="fr",
        email_status="pending",
    )
    async with TestSessionLocal() as s:
        s.add(notif)
        await s.commit()
        await s.refresh(notif)
        notif_id = notif.id

    provider = FakeEmailProvider(behavior="success")
    processed = await run_once(TestSessionLocal, provider)
    assert processed >= 1
    assert len(provider.sent_calls) >= 1

    # Conserver l'identifiant de la notification créée et vérifier qu'elle est email_status='sent'
    async with TestSessionLocal() as s:
        reloaded = (await s.execute(select(Notification).where(Notification.id == notif_id))).scalar_one()
        assert reloaded.email_status == "sent"


@pytest.mark.asyncio
async def test_lifespan_does_not_start_worker_when_disabled(monkeypatch):
    import asyncio
    from fastapi import FastAPI
    import app.main as main_module

    monkeypatch.setattr(main_module.settings, "EMAIL_WORKER_ENABLED", False)

    loop_started = False

    async def fake_loop(*args, **kwargs):
        nonlocal loop_started
        loop_started = True

    monkeypatch.setattr("app.services.notification_worker.email_worker_loop", fake_loop)
    monkeypatch.setattr(main_module, "engine", None)
    monkeypatch.setattr(main_module, "_run_migrations", lambda: None)
    monkeypatch.setattr(main_module, "init_db", lambda: asyncio.sleep(0))
    monkeypatch.setattr(main_module, "_fail_orphan_jobs_on_startup", lambda: asyncio.sleep(0))

    dummy_app = FastAPI(lifespan=main_module.lifespan)
    async with main_module.lifespan(dummy_app):
        await asyncio.sleep(0.01)

    assert loop_started is False


@pytest.mark.asyncio
async def test_sweep_overdue_bookings_creates_notification_once(worker_setup):
    from tests.conftest import TestSessionLocal
    from app.models import Booking, POI, POIManager
    from app.services.notification_worker import sweep_overdue_bookings
    tenant, user = worker_setup

    async with TestSessionLocal() as s:
        poi = POI(
            tenant_id=tenant.id,
            slug="sweep-poi",
            name="Sweep POI",
            city="Alger",
            booking_mode="manual_confirm",
        )
        s.add(poi)
        await s.flush()

        partner = User(
            tenant_id=tenant.id,
            email="partner_sweep@example.com",
            hashed_password="pw",
            is_active=True,
        )
        s.add(partner)
        await s.flush()

        s.add(POIManager(tenant_id=tenant.id, poi_id=poi.id, user_id=partner.id))

        booking = Booking(
            tenant_id=tenant.id,
            user_id=user.id,
            poi_id=poi.id,
            adapter_type="tour",
            status="requested",
            booking_mode="manual_confirm",
            respond_by=utcnow() - timedelta(hours=2),
            currency="DZD",
        )
        s.add(booking)
        await s.commit()
        booking_id = booking.id

    # 1. Sweep passes requested -> expired and creates notifications
    expired = await sweep_overdue_bookings(TestSessionLocal)
    assert expired == 1

    async with TestSessionLocal() as s:
        b = (await s.execute(select(Booking).where(Booking.id == booking_id))).scalar_one()
        assert b.status == "expired"

        notifs = (
            await s.execute(
                select(Notification).where(
                    Notification.tenant_id == tenant.id,
                    Notification.booking_id == booking_id,
                )
            )
        ).scalars().all()
        # 1 traveller (email pending), 1 partner (email skipped)
        assert len(notifs) == 2
        traveller_notif = next(n for n in notifs if n.user_id == user.id)
        assert traveller_notif.email_status == "pending"
        partner_notif = next(n for n in notifs if n.user_id == partner.id)
        assert partner_notif.email_status == "skipped"

    # 2. Second sweep must NOT create duplicate notifications nor re-expire
    expired_2 = await sweep_overdue_bookings(TestSessionLocal)
    assert expired_2 == 0

    async with TestSessionLocal() as s:
        notifs_after = (
            await s.execute(
                select(Notification).where(
                    Notification.tenant_id == tenant.id,
                    Notification.booking_id == booking_id,
                )
            )
        ).scalars().all()
        assert len(notifs_after) == 2
