"""Tenant tests — 4 tests."""
import pytest


@pytest.mark.asyncio
async def test_get_current_tenant(client, test_tenant):
    response = await client.get(
        "/api/v1/tenants/current",
        headers={"X-Tenant-Slug": "test-tenant"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["slug"] == "test-tenant"


@pytest.mark.asyncio
async def test_list_tenants_admin_only(client, auth_headers, admin_headers):
    # Regular user should get 403
    response = await client.get("/api/v1/tenants/", headers=auth_headers)
    assert response.status_code == 403

    # Admin should succeed
    response = await client.get("/api/v1/tenants/", headers=admin_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


@pytest.mark.asyncio
async def test_create_tenant_duplicate_slug(client, admin_headers, test_tenant):
    response = await client.post(
        "/api/v1/tenants/",
        headers=admin_headers,
        json={
            "slug": "test-tenant",
            "name": "Duplicate",
            "default_language": "fr",
            "default_currency": "DZD",
        },
    )
    assert response.status_code == 400
    assert "already exists" in response.json()["detail"]


@pytest.mark.asyncio
async def test_create_tenant_success(client, admin_headers):
    response = await client.post(
        "/api/v1/tenants/",
        headers=admin_headers,
        json={
            "slug": "tunisia",
            "name": "Discover Tunisia",
            "default_language": "fr",
            "supported_languages": ["fr", "ar"],
            "default_currency": "TND",
            "primary_color": "#CE1126",
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert data["slug"] == "tunisia"
    assert data["default_currency"] == "TND"
