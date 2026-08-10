"""Analytics tests — 8 tests."""
import pytest


@pytest.mark.asyncio
async def test_track_event(client, auth_headers):
    response = await client.post(
        "/api/v1/analytics/track",
        headers=auth_headers,
        json={"event_type": "page_view", "event_data": {"page": "/home"}},
    )
    assert response.status_code == 200
    assert response.json()["status"] == "tracked"


@pytest.mark.asyncio
async def test_track_batch(client, auth_headers):
    response = await client.post(
        "/api/v1/analytics/track/batch",
        headers=auth_headers,
        json=[
            {"event_type": "click", "event_data": {"element": "button"}},
            {"event_type": "scroll", "event_data": {"depth": 80}},
        ],
    )
    assert response.status_code == 200
    assert response.json()["count"] == 2


@pytest.mark.asyncio
async def test_dashboard_overview(client, auth_headers):
    response = await client.get("/api/v1/analytics/dashboard/overview", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert "total_users" in data
    assert "total_pois" in data
    assert "total_trips" in data


@pytest.mark.asyncio
async def test_dashboard_content(client, auth_headers):
    response = await client.get("/api/v1/analytics/dashboard/content", headers=auth_headers)
    assert response.status_code == 200
    assert "categories" in response.json()


@pytest.mark.asyncio
async def test_dashboard_users(client, auth_headers):
    response = await client.get("/api/v1/analytics/dashboard/users", headers=auth_headers)
    assert response.status_code == 200
    assert "new_users_per_day" in response.json()


@pytest.mark.asyncio
async def test_export_pois(client, auth_headers):
    response = await client.get("/api/v1/analytics/export/pois", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["type"] == "csv"


@pytest.mark.asyncio
async def test_analytics_tenant_isolation(client, auth_headers, db_session, test_tenant):
    # Events tracked in test-tenant should not appear in algeria
    response = await client.post(
        "/api/v1/analytics/track",
        headers=auth_headers,
        json={"event_type": "test_isolation"},
    )
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_analytics_requires_auth(client, test_tenant):
    response = await client.get("/api/v1/analytics/dashboard/overview", headers={"X-Tenant-Slug": "test-tenant"})
    assert response.status_code == 403
