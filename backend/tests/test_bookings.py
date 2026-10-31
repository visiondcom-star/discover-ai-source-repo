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
        categories=["historical"],
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
        categories=["historical"],
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
        categories=["culture"],
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
        categories=["culture"],
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
        categories=["nature"],
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


# ---- Helpers pour les tests de consentement ---------------------------------

async def _poi(db_session, tenant, slug, mode="request"):
    from app.models import POI

    poi = POI(
        tenant_id=tenant.id,
        slug=slug,
        name=f"POI {slug}",
        city="Alger",
        categories=["culture"],
        is_active=True,
        booking_mode=mode,
    )
    db_session.add(poi)
    await db_session.commit()
    await db_session.refresh(poi)
    return poi


async def _booking(db_session, tenant, user, poi, status="pending", consent_given=False, mode="request"):
    from app.models import Booking

    booking = Booking(
        tenant_id=tenant.id,
        user_id=user.id,
        poi_id=poi.id,
        adapter_type="hotel",
        status=status,
        consent_given=consent_given,
        currency="DZD",
        booking_mode=mode,
    )
    db_session.add(booking)
    await db_session.commit()
    await db_session.refresh(booking)
    return booking


async def _consent(client, auth_headers, booking_id, consent=True):
    return await client.post(
        f"/api/v1/bookings/{booking_id}/consent",
        headers=auth_headers,
        json={"consent": consent},
    )


async def _notif_count(db_session, tenant_id, booking_id=None):
    from sqlalchemy import func, select
    from app.models import Notification

    stmt = select(func.count()).select_from(Notification).where(Notification.tenant_id == tenant_id)
    if booking_id is not None:
        stmt = stmt.where(Notification.booking_id == booking_id)
    res = await db_session.execute(stmt)
    return res.scalar_one()


# ---- Tests des gardes de statut sur give_consent -----------------------------

@pytest.mark.asyncio
async def test_consent_true_on_cancelled_booking_rejected(client, auth_headers, db_session, test_tenant, test_user):
    poi = await _poi(db_session, test_tenant, "cancelled-consent-poi", mode="request")
    booking = await _booking(
        db_session, test_tenant, test_user, poi, status="cancelled", consent_given=False, mode="request"
    )

    notifs_before = await _notif_count(db_session, test_tenant.id, booking.id)

    response = await _consent(client, auth_headers, booking.id, consent=True)
    assert response.status_code == 409
    assert response.json()["detail"] == "Booking cannot be consented in its current state"

    await db_session.refresh(booking)
    assert booking.status == "cancelled"
    assert booking.consent_given is False

    notifs_after = await _notif_count(db_session, test_tenant.id, booking.id)
    assert notifs_after == notifs_before


@pytest.mark.asyncio
async def test_consent_true_on_confirmed_booking_rejected(client, auth_headers, db_session, test_tenant, test_user):
    poi = await _poi(db_session, test_tenant, "confirmed-consent-poi", mode="request")
    booking = await _booking(
        db_session, test_tenant, test_user, poi, status="confirmed", consent_given=True, mode="request"
    )

    notifs_before = await _notif_count(db_session, test_tenant.id, booking.id)

    response = await _consent(client, auth_headers, booking.id, consent=True)
    assert response.status_code == 409
    assert response.json()["detail"] == "Booking cannot be consented in its current state"

    await db_session.refresh(booking)
    assert booking.status == "confirmed"

    notifs_after = await _notif_count(db_session, test_tenant.id, booking.id)
    assert notifs_after == notifs_before


@pytest.mark.asyncio
async def test_consent_false_on_confirmed_booking_rejected(client, auth_headers, db_session, test_tenant, test_user):
    poi = await _poi(db_session, test_tenant, "confirmed-cancel-consent-poi", mode="request")
    booking = await _booking(
        db_session, test_tenant, test_user, poi, status="confirmed", consent_given=True, mode="request"
    )

    response = await _consent(client, auth_headers, booking.id, consent=False)
    assert response.status_code == 409
    assert response.json()["detail"] == "Booking cannot be consented in its current state"

    await db_session.refresh(booking)
    assert booking.status == "confirmed"


@pytest.mark.asyncio
@pytest.mark.parametrize("status", ["requested", "confirmed", "declined", "expired", "cancelled"])
async def test_consent_false_on_non_pending_manual_confirm_rejected(
    client, auth_headers, db_session, test_tenant, test_user, status
):
    poi = await _poi(db_session, test_tenant, f"manual-{status}-poi", mode="manual_confirm")
    booking = await _booking(
        db_session,
        test_tenant,
        test_user,
        poi,
        status=status,
        consent_given=(status in ("requested", "confirmed")),
        mode="manual_confirm",
    )

    response = await _consent(client, auth_headers, booking.id, consent=False)
    assert response.status_code == 409
    assert response.json()["detail"] == "Booking cannot be consented in its current state"

    await db_session.refresh(booking)
    assert booking.status == status


@pytest.mark.asyncio
async def test_consent_non_regression_from_pending(client, auth_headers, db_session, test_tenant, test_user):
    # 1) Mode request: pending -> consent=True -> confirmed
    poi_req = await _poi(db_session, test_tenant, "nr-req-true", mode="request")
    b_req_true = await _booking(db_session, test_tenant, test_user, poi_req, status="pending", mode="request")
    r1 = await _consent(client, auth_headers, b_req_true.id, consent=True)
    assert r1.status_code == 200
    assert r1.json()["status"] == "confirmed"
    assert r1.json()["consent_given"] is True

    # 2) Mode request: pending -> consent=False -> cancelled
    poi_req_f = await _poi(db_session, test_tenant, "nr-req-false", mode="request")
    b_req_false = await _booking(db_session, test_tenant, test_user, poi_req_f, status="pending", mode="request")
    r2 = await _consent(client, auth_headers, b_req_false.id, consent=False)
    assert r2.status_code == 200
    assert r2.json()["status"] == "cancelled"

    # 3) Mode manual_confirm: pending -> consent=True -> requested
    poi_man = await _poi(db_session, test_tenant, "nr-man-true", mode="manual_confirm")
    b_man_true = await _booking(db_session, test_tenant, test_user, poi_man, status="pending", mode="manual_confirm")
    r3 = await _consent(client, auth_headers, b_man_true.id, consent=True)
    assert r3.status_code == 200
    assert r3.json()["status"] == "requested"
    assert r3.json()["consent_given"] is True

    # 4) Mode manual_confirm: pending -> consent=False -> cancelled
    poi_man_f = await _poi(db_session, test_tenant, "nr-man-false", mode="manual_confirm")
    b_man_false = await _booking(db_session, test_tenant, test_user, poi_man_f, status="pending", mode="manual_confirm")
    r4 = await _consent(client, auth_headers, b_man_false.id, consent=False)
    assert r4.status_code == 200
    assert r4.json()["status"] == "cancelled"
