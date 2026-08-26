"""Trip tests — 6 tests."""
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
        budget_currency="DZD",
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
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_generate_trip_currency_defaults_to_tenant(
    client, auth_headers, db_session, test_tenant
):
    """Default budget_currency must derive from the tenant, not a hardcoded
    literal. The seeded tenant here uses DZD, so an unspecified currency must
    land on DZD."""
    from app.models import POI

    poi = POI(
        tenant_id=test_tenant.id,
        slug="currency-poi",
        name="Currency POI",
        city="Alger",
        category="historical",
        duration_minutes=60,
        is_active=True,
    )
    db_session.add(poi)
    await db_session.commit()

    # No budget_currency in the payload on purpose.
    response = await client.post(
        "/api/v1/trips/generate",
        headers=auth_headers,
        json={
            "interests": ["historical"],
            "budget_level": "medium",
            "num_days": 1,
            "travel_style": "balanced",
            "group_type": "solo",
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert data["budget_currency"] == "DZD"


@pytest.mark.asyncio
async def test_generate_trip_currency_defaults_to_other_tenant_currency(
    client, db_session
):
    """A second tenant with a distinct currency must get its own currency when
    the request omits budget_currency — proving the default is not a fixed
    literal like DZD."""
    from app.models import Tenant, User, POI
    from app.core.security import get_password_hash

    # Create a distinct-currency tenant (morocco, MAD) and its user.
    tenant = Tenant(
        slug="morocco",
        name="Discover Morocco",
        default_language="fr",
        default_currency="MAD",
    )
    db_session.add(tenant)
    await db_session.commit()
    await db_session.refresh(tenant)

    user = User(
        tenant_id=tenant.id,
        email="demo@morocco.travel",
        hashed_password=get_password_hash("demo1234"),
        full_name="Demo Morocco",
        is_active=True,
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)

    poi = POI(
        tenant_id=tenant.id,
        slug="morocco-poi",
        name="Marrakech POI",
        city="Marrakech",
        category="historical",
        duration_minutes=60,
        is_active=True,
    )
    db_session.add(poi)
    await db_session.commit()

    # Authenticate against the morocco tenant.
    login = await client.post(
        "/api/v1/auth/login",
        headers={"X-Tenant-Slug": "morocco"},
        json={"email": "demo@morocco.travel", "password": "demo1234"},
    )
    assert login.status_code == 200
    token = login.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}", "X-Tenant-Slug": "morocco"}

    response = await client.post(
        "/api/v1/trips/generate",
        headers=headers,
        json={
            "interests": ["historical"],
            "budget_level": "low",
            "num_days": 1,
            "travel_style": "balanced",
            "group_type": "solo",
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert data["budget_currency"] == "MAD"
