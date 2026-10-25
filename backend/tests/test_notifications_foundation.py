"""Tests for notifications model, migration and users.locale."""
import asyncio
import uuid
import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from app.models import Notification, Tenant, User, Booking, POI, utcnow
from app.main import ALEMBIC_INI


@pytest.mark.asyncio
async def test_migration_upgrade_downgrade_upgrade():
    """Verify Alembic 0014_notifications upgrades, downgrades and re-upgrades cleanly."""
    def _run_alembic_cycle():
        alembic_cfg = Config(str(ALEMBIC_INI))
        alembic_cfg.attributes["configure_logger"] = False
        command.downgrade(alembic_cfg, "0013_partner_poi_managers")
        command.upgrade(alembic_cfg, "0014_notifications")
        command.downgrade(alembic_cfg, "0013_partner_poi_managers")
        command.upgrade(alembic_cfg, "head")

    await asyncio.to_thread(_run_alembic_cycle)


@pytest.mark.asyncio
async def test_notifications_unique_constraint_with_booking(db_session, test_tenant, test_user):
    """(tenant_id, user_id, booking_id, type) must be unique when booking_id is not null."""
    poi = POI(
        tenant_id=test_tenant.id,
        slug="test-poi-unique",
        name="Test POI",
        city="Alger",
    )
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

    n1 = Notification(
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        booking_id=booking.id,
        type="booking_confirmed",
        payload={"message": "Confirmed"},
        locale="fr",
    )
    db_session.add(n1)
    await db_session.commit()

    # Inserting duplicate with exact same (tenant, user, booking, type) should raise IntegrityError
    n2 = Notification(
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        booking_id=booking.id,
        type="booking_confirmed",
        payload={"message": "Duplicate"},
        locale="fr",
    )
    db_session.add(n2)
    with pytest.raises(IntegrityError):
        await db_session.commit()
    await db_session.rollback()


@pytest.mark.asyncio
async def test_notifications_allows_multiple_null_booking_id(db_session, test_tenant, test_user):
    """When booking_id IS NULL, partial unique index should not prevent multiple notifications of same type."""
    n1 = Notification(
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        booking_id=None,
        type="system_alert",
        payload={"message": "Alert 1"},
        locale="fr",
    )
    n2 = Notification(
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        booking_id=None,
        type="system_alert",
        payload={"message": "Alert 2"},
        locale="fr",
    )
    db_session.add(n1)
    db_session.add(n2)
    await db_session.commit()
    assert n1.id != n2.id


@pytest.mark.asyncio
async def test_patch_me_validates_locale(client, auth_headers, db_session, test_tenant, test_user):
    """PATCH /auth/me validates locale against tenant.supported_languages."""
    test_tenant.supported_languages = ["fr", "en", "ar"]
    db_session.add(test_tenant)
    await db_session.commit()

    client_headers = dict(auth_headers)

    # 1. Valid locale
    resp = await client.patch("/api/v1/auth/me", headers=client_headers, json={"locale": "en"})
    assert resp.status_code == 200, resp.text
    assert resp.json()["locale"] == "en"

    # Verify on GET /auth/me
    get_resp = await client.get("/api/v1/auth/me", headers=client_headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["locale"] == "en"

    # 2. Invalid locale
    bad_resp = await client.patch("/api/v1/auth/me", headers=client_headers, json={"locale": "de"})
    assert bad_resp.status_code == 422
    assert "Locale 'de' not supported" in bad_resp.json()["detail"]

    # 3. Verify user response exposes locale
    assert "locale" in get_resp.json()
