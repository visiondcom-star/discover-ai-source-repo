"""Authentication tests — 5 tests."""
import pytest


@pytest.mark.asyncio
async def test_register_user(client, test_tenant):
    response = await client.post(
        "/api/v1/auth/register",
        headers={"X-Tenant-Slug": "test-tenant"},
        json={"email": "new@example.com", "password": "newpass123", "full_name": "New User"},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["email"] == "new@example.com"
    assert data["full_name"] == "New User"


@pytest.mark.asyncio
async def test_register_duplicate_email(client, test_user, test_tenant):
    response = await client.post(
        "/api/v1/auth/register",
        headers={"X-Tenant-Slug": "test-tenant"},
        json={"email": "test@example.com", "password": "testpass123"},
    )
    assert response.status_code == 400
    assert "already registered" in response.json()["detail"]


@pytest.mark.asyncio
async def test_login_success(client, test_user, test_tenant):
    response = await client.post(
        "/api/v1/auth/login",
        headers={"X-Tenant-Slug": "test-tenant"},
        json={"email": "test@example.com", "password": "testpass123"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"


@pytest.mark.asyncio
async def test_login_wrong_password(client, test_user, test_tenant):
    response = await client.post(
        "/api/v1/auth/login",
        headers={"X-Tenant-Slug": "test-tenant"},
        json={"email": "test@example.com", "password": "wrongpass"},
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_login_wrong_tenant(client, test_user):
    # User exists in test-tenant, not in algeria
    response = await client.post(
        "/api/v1/auth/login",
        headers={"X-Tenant-Slug": "algeria"},
        json={"email": "test@example.com", "password": "testpass123"},
    )
    assert response.status_code == 401
