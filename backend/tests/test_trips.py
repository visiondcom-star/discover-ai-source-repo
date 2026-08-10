"""Trip tests — 4 tests."""
import pytest


@pytest.mark.asyncio
async def test_generate_trip(client, auth_headers, db_session, test_tenant):
    from app.models import POI
    # Add a POI for trip generation
    poi = POI(
        tenant_id=test_tenant.id,
        slug="trip-poi",
        name="Trip POI",
        city="Alger",
        category="historical",
        duration_minutes=60,
        is_active=True,
    )
    db_session.add(poi)
    await db_session.commit()

    response = await client.post(
        "/api/v1/trips/generate",
        headers=auth_headers,
        json={
            "interests": ["historical"],
            "budget_level": "medium",
            "num_days": 2,
            "budget_currency": "DZD",
            "travel_style": "balanced",
            "group_type": "solo",
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert "id" in data
    assert data["num_days"] == 2


@pytest.mark.asyncio
async def test_list_my_trips(client, auth_headers):
    response = await client.get("/api/v1/trips/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


@pytest.mark.asyncio
async def test_get_trip_details(client, auth_headers, db_session, test_tenant, test_user):
    from app.models import Trip, TripItem, POI
    poi = POI(
        tenant_id=test_tenant.id,
        slug="detail-poi",
        name="Detail POI",
        city="Alger",
        category="culture",
        duration_minutes=90,
        is_active=True,
    )
    db_session.add(poi)
    await db_session.flush()

    trip = Trip(
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        title="Test Trip",
        num_days=1,
        status="planned",
    )
    db_session.add(trip)
    await db_session.flush()

    item = TripItem(trip_id=trip.id, poi_id=poi.id, day_number=1, order_index=0)
    db_session.add(item)
    await db_session.commit()

    response = await client.get(f"/api/v1/trips/{trip.id}", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["title"] == "Test Trip"
    assert len(data["items"]) == 1


@pytest.mark.asyncio
async def test_trip_requires_auth(client, test_tenant):
    response = await client.post(
        "/api/v1/trips/generate",
        headers={"X-Tenant-Slug": "test-tenant"},
        json={"num_days": 1, "budget_level": "low"},
    )
    assert response.status_code == 403
