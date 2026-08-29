"""Booking tests — 6 tests."""
import pytest


@pytest.mark.asyncio
async def test_create_booking(client, auth_headers, db_session, test_tenant, test_user):
    from app.models import POI
    poi = POI(
        tenant_id=test_tenant.id,
        slug="booking-poi",
        name="Booking POI",
        city="Alger",
        category="historical",
        is_active=True,
    )
    db_session.add(poi)
    await db_session.commit()
    await db_session.refresh(poi)

    response = await client.post(
        "/api/v1/bookings/",
        headers=auth_headers,
        json={"poi_id": str(poi.id), "adapter_type": "tour", "booking_data": {"date": "2024-10-01"}},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["status"] == "pending"
    assert data["consent_given"] == False


@pytest.mark.asyncio
async def test_create_booking_currency_defaults_to_tenant(client, db_session):
    """Booking currency must derive from the tenant, not a hardcoded literal.
    A MAD tenant must yield MAD bookings even though the payload never mentions
    a currency."""
    from app.models import Tenant, User, POI
    from app.core.security import get_password_hash

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
        slug="morocco-booking-poi",
        name="Marrakech Booking POI",
        city="Marrakech",
        category="historical",
        is_active=True,
    )
    db_session.add(poi)
    await db_session.commit()
    await db_session.refresh(poi)

    login = await client.post(
        "/api/v1/auth/login",
        headers={"X-Tenant-Slug": "morocco"},
        json={"email": "demo@morocco.travel", "password": "demo1234"},
    )
    assert login.status_code == 200
    headers = {
        "Authorization": f"Bearer {login.json()['access_token']}",
        "X-Tenant-Slug": "morocco",
    }

    response = await client.post(
        "/api/v1/bookings/",
        headers=headers,
        json={"poi_id": str(poi.id), "adapter_type": "tour"},
    )
    assert response.status_code == 201
    assert response.json()["currency"] == "MAD"


@pytest.mark.asyncio
async def test_list_bookings(client, auth_headers):
    response = await client.get("/api/v1/bookings/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


@pytest.mark.asyncio
async def test_give_consent_requires_explicit_field(
    client, auth_headers, db_session, test_tenant, test_user
):
    """A request that omits `consent` entirely must be rejected (422), not
    silently treated as consent given. Guards against ConsentRequest
    regaining a `= True` default — the booking must stay pending/unconsented
    when the body doesn't say so explicitly."""
    from app.models import POI, Booking

    poi = POI(
        tenant_id=test_tenant.id,
        slug="consent-missing-field-poi",
        name="Consent Missing Field POI",
        city="Alger",
        category="culture",
        is_active=True,
    )
    db_session.add(poi)
    await db_session.flush()

    booking = Booking(
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        poi_id=poi.id,
        adapter_type="hotel",
        status="pending",
        consent_given=False,
        currency="DZD",
    )
    db_session.add(booking)
    await db_session.commit()
    await db_session.refresh(booking)

    response = await client.post(
        f"/api/v1/bookings/{booking.id}/consent",
        headers=auth_headers,
        json={},
    )
    assert response.status_code == 422

    await db_session.refresh(booking)
    assert booking.status == "pending"
    assert booking.consent_given is False


@pytest.mark.asyncio
async def test_give_consent(client, auth_headers, db_session, test_tenant, test_user):
    from app.models import POI, Booking
    poi = POI(
        tenant_id=test_tenant.id,
        slug="consent-poi",
        name="Consent POI",
        city="Alger",
        category="culture",
        is_active=True,
    )
    db_session.add(poi)
    await db_session.flush()

    booking = Booking(
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        poi_id=poi.id,
        adapter_type="hotel",
        status="pending",
        consent_given=False,
        currency="DZD",
    )
    db_session.add(booking)
    await db_session.commit()
    await db_session.refresh(booking)

    response = await client.post(
        f"/api/v1/bookings/{booking.id}/consent",
        headers=auth_headers,
        json={"consent": True},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "confirmed"
    assert data["consent_given"] == True


@pytest.mark.asyncio
async def test_cancel_booking(client, auth_headers, db_session, test_tenant, test_user):
    from app.models import POI, Booking
    poi = POI(
        tenant_id=test_tenant.id,
        slug="cancel-poi",
        name="Cancel POI",
        city="Alger",
        category="nature",
        is_active=True,
    )
    db_session.add(poi)
    await db_session.flush()

    booking = Booking(
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        poi_id=poi.id,
        adapter_type="restaurant",
        status="pending",
        currency="DZD",
    )
    db_session.add(booking)
    await db_session.commit()
    await db_session.refresh(booking)

    response = await client.post(
        f"/api/v1/bookings/{booking.id}/cancel",
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json()["status"] == "cancelled"


@pytest.mark.asyncio
async def test_list_adapters(client, auth_headers):
    response = await client.get("/api/v1/bookings/adapters/available", headers=auth_headers)
    assert response.status_code == 200
    assert "adapters" in response.json()
