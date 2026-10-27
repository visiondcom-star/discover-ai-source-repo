"""Unit tests for notification_service and notification_templates."""
import uuid
import pytest
from types import SimpleNamespace
from sqlalchemy import select

from app.models import Booking, Notification, POI, Tenant, User
from app.services.notification_service import create_notification, resolve_locale
from app.services.notification_templates import NOTIFICATION_TEMPLATES, render_notification


def test_resolve_locale_level_1_user():
    """Level 1: user.locale wins when present."""
    user = SimpleNamespace(locale="fr")
    tenant = SimpleNamespace(default_language="ar")
    assert resolve_locale(user, tenant) == "fr"


def test_resolve_locale_level_2_tenant():
    """Level 2: fallback to tenant.default_language when user.locale is None or empty."""
    user1 = SimpleNamespace(locale=None)
    user2 = SimpleNamespace(locale="   ")
    tenant = SimpleNamespace(default_language="ar")
    assert resolve_locale(user1, tenant) == "ar"
    assert resolve_locale(user2, tenant) == "ar"
    assert resolve_locale(None, tenant) == "ar"


def test_resolve_locale_level_3_fallback_en():
    """Level 3: fallback to 'en' when neither user nor tenant specifies language."""
    user = SimpleNamespace(locale=None)
    tenant = SimpleNamespace(default_language=None)
    assert resolve_locale(user, tenant) == "en"
    assert resolve_locale(None, None) == "en"


def test_templates_fr_and_en_for_all_types():
    """All notification types must define fr and en templates."""
    required_types = [
        "booking_request_received",
        "booking_confirmed",
        "booking_declined",
        "booking_expired",
    ]
    for t in required_types:
        assert t in NOTIFICATION_TEMPLATES, f"Missing template for {t}"
        assert "fr" in NOTIFICATION_TEMPLATES[t]
        assert "en" in NOTIFICATION_TEMPLATES[t]
        assert "title" in NOTIFICATION_TEMPLATES[t]["fr"]
        assert "message" in NOTIFICATION_TEMPLATES[t]["fr"]
        assert "title" in NOTIFICATION_TEMPLATES[t]["en"]
        assert "message" in NOTIFICATION_TEMPLATES[t]["en"]


def test_render_notification_default_poi_name_fr_and_en():
    """Default poi_name is localized: 'votre destination' for fr, 'your destination' for en."""
    # French
    title_fr, msg_fr = render_notification("booking_confirmed", "fr", {})
    assert "votre destination" in msg_fr

    title_fr_none, msg_fr_none = render_notification("booking_confirmed", "fr", {"poi_name": None})
    assert "votre destination" in msg_fr_none

    # English
    title_en, msg_en = render_notification("booking_confirmed", "en", {})
    assert "your destination" in msg_en

    title_en_none, msg_en_none = render_notification("booking_confirmed", "en", {"poi_name": None})
    assert "your destination" in msg_en_none


def test_render_notification_fallback_locale():
    """Unsupported locale falls back to 'en' and renders exact 'Booking confirmed'."""
    title, msg = render_notification("booking_confirmed", "de", {"poi_name": "Casbah"})
    assert title == "Booking confirmed"
    assert "Casbah" in msg


@pytest.mark.asyncio
async def test_create_notification_persists_in_same_session(db_session, test_tenant, test_user):
    """create_notification persists cleanly inside caller's transaction."""
    poi = POI(tenant_id=test_tenant.id, slug="poi-notif-svc", name="Jardin d'Essai", city="Alger")
    db_session.add(poi)
    await db_session.flush()

    booking = Booking(
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        poi_id=poi.id,
        adapter_type="tour",
        status="pending",
        currency="DZD",
    )
    db_session.add(booking)
    await db_session.flush()

    notif = await create_notification(
        db=db_session,
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        type_="booking_confirmed",
        booking=booking,
        payload={"poi_name": poi.name},
        user=test_user,
        tenant=test_tenant,
    )
    assert notif is not None
    assert notif.id is not None
    assert notif.locale == "fr"  # test_tenant.default_language is "fr"
    assert notif.type == "booking_confirmed"

    await db_session.commit()

    # Re-read
    loaded = (await db_session.execute(select(Notification).where(Notification.id == notif.id))).scalar_one()
    assert loaded.payload["poi_name"] == "Jardin d'Essai"


@pytest.mark.asyncio
async def test_create_notification_ignores_duplicate_without_breaking_transaction(
    db_session, test_tenant, test_user
):
    """A duplicate notification with same (tenant, user, booking, type) returns None and does not abort outer transaction."""
    poi = POI(tenant_id=test_tenant.id, slug="poi-dup", name="Notre Dame d'Afrique", city="Alger")
    db_session.add(poi)
    await db_session.flush()

    booking = Booking(
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        poi_id=poi.id,
        adapter_type="tour",
        status="pending",
        currency="DZD",
    )
    db_session.add(booking)
    await db_session.flush()

    # First creation -> success
    n1 = await create_notification(
        db=db_session,
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        type_="booking_confirmed",
        booking=booking,
        payload={"step": 1},
        tenant=test_tenant,
    )
    assert n1 is not None

    # Second creation with identical (tenant, user, booking, type) -> returns None silently
    n2 = await create_notification(
        db=db_session,
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        type_="booking_confirmed",
        booking=booking,
        payload={"step": 2},
        tenant=test_tenant,
    )
    assert n2 is None

    # Outer transaction must still be able to commit!
    await db_session.commit()

    # Check only 1 row was stored
    result = await db_session.execute(
        select(Notification).where(
            Notification.tenant_id == test_tenant.id,
            Notification.booking_id == booking.id,
            Notification.type == "booking_confirmed",
        )
    )
    rows = result.scalars().all()
    assert len(rows) == 1
    assert rows[0].payload["step"] == 1


@pytest.mark.asyncio
async def test_create_notification_email_false_creates_skipped(db_session, test_tenant, test_user):
    """create_notification with email=False creates notification with email_status='skipped'."""
    n = await create_notification(
        db=db_session,
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        type_="custom_alert",
        payload={"msg": "in-app only"},
        email=False,
    )
    assert n is not None
    assert n.email_status == "skipped"

    await db_session.commit()
    loaded = (await db_session.execute(select(Notification).where(Notification.id == n.id))).scalar_one()
    assert loaded.email_status == "skipped"
