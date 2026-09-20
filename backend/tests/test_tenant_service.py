"""Création de tenants : service et script d'administration."""
import pytest
from sqlalchemy import func, select

from app.core.security import verify_password
from app.create_tenant import create_from_args, parse_args
from app.models import User
from app.schemas import TenantCreate
from app.services.tenant_service import TenantAlreadyExists, create_tenant_with_admin


def _data(slug="tunisia"):
    return TenantCreate(
        slug=slug,
        name="Discover Tunisia",
        default_language="fr",
        default_currency="TND",
    )


async def _count_users(session):
    return (await session.execute(select(func.count()).select_from(User))).scalar_one()


async def test_creates_tenant_and_first_admin(db_session):
    tenant, admin = await create_tenant_with_admin(
        db_session, _data(), "boss@example.com", "supersecret1", "Boss"
    )
    assert tenant.slug == "tunisia"
    assert tenant.default_currency == "TND"
    assert admin.tenant_id == tenant.id
    assert admin.is_admin and admin.is_active
    assert admin.hashed_password != "supersecret1"
    assert verify_password("supersecret1", admin.hashed_password)


async def test_duplicate_slug_is_refused_and_creates_nothing(db_session, test_tenant):
    before = await _count_users(db_session)
    with pytest.raises(TenantAlreadyExists):
        await create_tenant_with_admin(
            db_session, _data(slug="test-tenant"), "boss@example.com", "supersecret1"
        )
    assert await _count_users(db_session) == before


async def test_first_admin_can_log_in_and_sees_only_own_tenant(
    client, db_session, test_tenant
):
    await create_tenant_with_admin(
        db_session, _data(), "boss@example.com", "supersecret1"
    )
    login = await client.post(
        "/api/v1/auth/login",
        headers={"X-Tenant-Slug": "tunisia"},
        json={"email": "boss@example.com", "password": "supersecret1"},
    )
    assert login.status_code == 200, login.text
    headers = {
        "Authorization": f"Bearer {login.json()['access_token']}",
        "X-Tenant-Slug": "tunisia",
    }
    response = await client.get("/api/v1/tenants/", headers=headers)
    assert response.status_code == 200
    assert [t["slug"] for t in response.json()] == ["tunisia"]


def test_cli_requires_mandatory_arguments():
    with pytest.raises(SystemExit):
        parse_args(["--slug", "tunisia"])


async def test_cli_creates_tenant_from_args(client):
    args = parse_args(
        [
            "--slug", "tunisia",
            "--name", "Discover Tunisia",
            "--language", "fr",
            "--currency", "TND",
            "--languages", "fr, ar",
            "--admin-email", "boss@example.com",
        ]
    )
    tenant, admin = await create_from_args(args, "supersecret1")
    assert tenant.supported_languages == ["fr", "ar"]
    assert admin.email == "boss@example.com"

    response = await client.get(
        "/api/v1/tenants/current", headers={"X-Tenant-Slug": "tunisia"}
    )
    assert response.status_code == 200
