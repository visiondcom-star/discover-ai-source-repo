"""Tests for notifications model, migration and users.locale."""
import asyncio
import os
import uuid
import asyncpg
import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import select, text
from sqlalchemy.engine import make_url
from sqlalchemy.exc import IntegrityError
from app.config import get_settings
from app.models import Notification, Tenant, User, Booking, POI, utcnow
from app.main import ALEMBIC_INI


@pytest.mark.asyncio
async def test_migration_upgrade_downgrade_upgrade(monkeypatch):
    """Verify Alembic migrations run cleanly on a throwaway isolated database."""
    test_db_url = os.getenv(
        "TEST_DATABASE_URL",
        "postgresql+asyncpg://postgres:postgres@localhost:5432/discoverai_test",
    )
    parsed_url = make_url(test_db_url)
    tmp_db_name = f"discoverai_migr_{uuid.uuid4().hex[:8]}"
    tmp_db_url = parsed_url.set(database=tmp_db_name).render_as_string(hide_password=False)

    admin_conn = await asyncpg.connect(
        user=parsed_url.username,
        password=parsed_url.password,
        host=parsed_url.host,
        port=parsed_url.port,
        database="postgres",
    )
    try:
        await admin_conn.execute(f"CREATE DATABASE {tmp_db_name}")
        tmp_conn = await asyncpg.connect(
            user=parsed_url.username,
            password=parsed_url.password,
            host=parsed_url.host,
            port=parsed_url.port,
            database=tmp_db_name,
        )
        try:
            await tmp_conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
        finally:
            await tmp_conn.close()

        def _run_alembic_cycle():
            monkeypatch.setenv("DATABASE_URL", tmp_db_url)
            get_settings.cache_clear()
            alembic_cfg = Config(str(ALEMBIC_INI))
            alembic_cfg.attributes["configure_logger"] = False
            command.upgrade(alembic_cfg, "head")
            command.downgrade(alembic_cfg, "0013_partner_poi_managers")
            command.upgrade(alembic_cfg, "0014_notifications")
            command.upgrade(alembic_cfg, "0015_notifications_worker_cols")
            command.downgrade(alembic_cfg, "0014_notifications")
            command.upgrade(alembic_cfg, "head")

        await asyncio.to_thread(_run_alembic_cycle)

        # 5. Check expected tables and columns exist
        verify_conn = await asyncpg.connect(
            user=parsed_url.username,
            password=parsed_url.password,
            host=parsed_url.host,
            port=parsed_url.port,
            database=tmp_db_name,
        )
        try:
            users_cols = {
                r["column_name"]
                for r in await verify_conn.fetch(
                    "SELECT column_name FROM information_schema.columns WHERE table_name = 'users'"
                )
            }
            notif_cols = {
                r["column_name"]
                for r in await verify_conn.fetch(
                    "SELECT column_name FROM information_schema.columns WHERE table_name = 'notifications'"
                )
            }
            assert "locale" in users_cols
            assert "first_attempt_at" in notif_cols
            assert "provider_message_id" in notif_cols
        finally:
            await verify_conn.close()

    finally:
        try:
            await admin_conn.execute(
                f"""
                SELECT pg_terminate_backend(pid)
                FROM pg_stat_activity
                WHERE datname = '{tmp_db_name}' AND pid <> pg_backend_pid()
                """
            )
            await admin_conn.execute(f"DROP DATABASE IF EXISTS {tmp_db_name}")
        finally:
            await admin_conn.close()
            get_settings.cache_clear()


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


@pytest.mark.asyncio
async def test_patch_me_tenant_without_supported_languages(client, auth_headers, db_session, test_tenant, test_user):
    """If tenant.supported_languages is empty or null, allow [tenant.default_language or 'en']."""
    test_tenant.supported_languages = []
    test_tenant.default_language = "fr"
    db_session.add(test_tenant)
    await db_session.commit()

    client_headers = dict(auth_headers)

    # fr allowed as tenant.default_language
    ok_resp = await client.patch("/api/v1/auth/me", headers=client_headers, json={"locale": "fr"})
    assert ok_resp.status_code == 200
    assert ok_resp.json()["locale"] == "fr"

    # en refused when default_language is fr
    bad_resp = await client.patch("/api/v1/auth/me", headers=client_headers, json={"locale": "en"})
    assert bad_resp.status_code == 422


@pytest.mark.asyncio
async def test_user_update_schema_has_only_locale():
    """Verify absence of full_name and preferences in UserUpdate schema."""
    from app.schemas import UserUpdate
    fields = UserUpdate.model_fields.keys()
    assert "locale" in fields
    assert "full_name" not in fields
    assert "preferences" not in fields


@pytest.mark.asyncio
async def test_notifications_model_worker_columns(db_session, test_tenant, test_user):
    """Verify first_attempt_at and provider_message_id persist and reload."""
    now = utcnow()
    n = Notification(
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        type="test_columns",
        payload={"k": "v"},
        locale="en",
        first_attempt_at=now,
        provider_message_id="msg_987",
    )
    db_session.add(n)
    await db_session.commit()
    await db_session.refresh(n)

    assert n.first_attempt_at == now
    assert n.provider_message_id == "msg_987"
