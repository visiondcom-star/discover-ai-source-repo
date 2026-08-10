"""Booking tests — 5 tests."""
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
async def test_list_bookings(client, auth_headers):
    response = await client.get("/api/v1/bookings/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


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
