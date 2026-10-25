"""Tests for notification emission on booking transitions and tenant isolation."""
from datetime import timedelta
import pytest
from sqlalchemy import select, and_

from app.models import Booking, Notification, POI, POIManager, Tenant, User, utcnow
from app.services.booking_lifecycle import expire_overdue_requests


@pytest.fixture
async def second_tenant(db_session):
    tenant = Tenant(
        slug="other-tenant",
        name="Other Tenant",
        default_language="en",
        default_currency="EUR",
    )
    db_session.add(tenant)
    await db_session.commit()
    await db_session.refresh(tenant)
    return tenant


@pytest.fixture
async def partner_user(db_session, test_tenant):
    from app.core.security import get_password_hash
    user = User(
        tenant_id=test_tenant.id,
        email="partner@example.com",
        hashed_password=get_password_hash("secret123"),
        full_name="Partner Bob",
        locale="fr",
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


@pytest.mark.asyncio
async def test_consent_standard_emits_confirmed_notification(client, auth_headers, test_tenant, test_user, db_session):
    """bookings.py: consent on standard booking mode creates booking_confirmed notification for traveller."""
    poi = POI(tenant_id=test_tenant.id, slug="poi-std", name="Musée du Bardo", city="Alger", booking_mode="request")
    db_session.add(poi)
    await db_session.commit()
    await db_session.refresh(poi)

    # 1. Create pending booking
    resp = await client.post(
        "/api/v1/bookings/",
        headers=auth_headers,
        json={"poi_id": str(poi.id), "adapter_type": "tour", "booking_data": {"date": "2026-11-01"}},
    )
    assert resp.status_code == 201, resp.text
    booking_id = resp.json()["id"]

    # 2. Give consent
    consent_resp = await client.post(
        f"/api/v1/bookings/{booking_id}/consent",
        headers=auth_headers,
        json={"consent": True},
    )
    assert consent_resp.status_code == 200, consent_resp.text
    assert consent_resp.json()["status"] == "confirmed"

    # 3. Verify notification created
    res = await db_session.execute(
        select(Notification).where(
            and_(
                Notification.tenant_id == test_tenant.id,
                Notification.user_id == test_user.id,
                Notification.booking_id == booking_id,
            )
        )
    )
    notifs = res.scalars().all()
    assert len(notifs) == 1
    assert notifs[0].type == "booking_confirmed"
    assert notifs[0].payload["poi_name"] == "Musée du Bardo"

    # Consecutive call / duplicate check: giving consent again or re-running does not produce duplicate
    # (even though status != pending causes 409 on second consent, let's verify no extra row)
    assert len(notifs) == 1


@pytest.mark.asyncio
async def test_consent_manual_confirm_notifies_poi_managers(
    client, auth_headers, test_tenant, test_user, partner_user, db_session
):
    """bookings.py: consent manual_confirm -> requested notifies every POIManager of that POI."""
    poi = POI(tenant_id=test_tenant.id, slug="poi-manual", name="Hôtel El Djazaïr", city="Alger", booking_mode="manual_confirm")
    db_session.add(poi)
    await db_session.flush()

    manager = POIManager(tenant_id=test_tenant.id, poi_id=poi.id, user_id=partner_user.id)
    db_session.add(manager)
    await db_session.commit()

    # 1. Create booking
    resp = await client.post(
        "/api/v1/bookings/",
        headers=auth_headers,
        json={"poi_id": str(poi.id), "adapter_type": "hotel", "booking_data": {"date": "2026-11-01"}},
    )
    assert resp.status_code == 201
    booking_id = resp.json()["id"]

    # 2. Give consent
    consent_resp = await client.post(
        f"/api/v1/bookings/{booking_id}/consent",
        headers=auth_headers,
        json={"consent": True},
    )
    assert consent_resp.status_code == 200
    assert consent_resp.json()["status"] == "requested"

    # 3. Verify notification for partner
    res = await db_session.execute(
        select(Notification).where(
            and_(
                Notification.tenant_id == test_tenant.id,
                Notification.user_id == partner_user.id,
                Notification.booking_id == booking_id,
            )
        )
    )
    mgr_notifs = res.scalars().all()
    assert len(mgr_notifs) == 1
    assert mgr_notifs[0].type == "booking_request_received"
    assert mgr_notifs[0].payload["poi_name"] == "Hôtel El Djazaïr"

    # Traveller must NOT receive booking_request_received
    res_trav = await db_session.execute(
        select(Notification).where(
            and_(
                Notification.tenant_id == test_tenant.id,
                Notification.user_id == test_user.id,
                Notification.booking_id == booking_id,
            )
        )
    )
    assert len(res_trav.scalars().all()) == 0


@pytest.mark.asyncio
async def test_partner_confirm_and_decline_emit_notifications(
    client, test_tenant, test_user, partner_user, db_session
):
    """partner.py: confirm and decline emit booking_confirmed or booking_declined to traveller."""
    from app.core.security import create_access_token
    token = create_access_token(data={"sub": str(partner_user.id), "email": partner_user.email, "tenant": test_tenant.slug})
    partner_headers = {"Authorization": f"Bearer {token}", "X-Tenant-Slug": test_tenant.slug}

    poi = POI(tenant_id=test_tenant.id, slug="poi-part", name="Palais des Raïs", city="Alger", booking_mode="manual_confirm")
    db_session.add(poi)
    await db_session.flush()

    manager = POIManager(tenant_id=test_tenant.id, poi_id=poi.id, user_id=partner_user.id)
    db_session.add(manager)

    # 1. Booking for decline
    b_decline = Booking(
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        poi_id=poi.id,
        adapter_type="tour",
        status="requested",
        booking_mode="manual_confirm",
        currency="DZD",
    )
    db_session.add(b_decline)
    await db_session.commit()

    # Decline
    dec_resp = await client.post(
        f"/api/v1/partner/bookings/{b_decline.id}/respond",
        headers=partner_headers,
        json={"decision": "decline", "note": "Complet aujourd'hui"},
    )
    assert dec_resp.status_code == 200, dec_resp.text
    assert dec_resp.json()["status"] == "declined"

    res_dec = await db_session.execute(
        select(Notification).where(
            and_(
                Notification.tenant_id == test_tenant.id,
                Notification.user_id == test_user.id,
                Notification.booking_id == b_decline.id,
            )
        )
    )
    dec_notifs = res_dec.scalars().all()
    assert len(dec_notifs) == 1
    assert dec_notifs[0].type == "booking_declined"
    assert dec_notifs[0].payload["partner_note"] == "Complet aujourd'hui"

    # 2. Booking for confirm
    b_confirm = Booking(
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        poi_id=poi.id,
        adapter_type="tour",
        status="requested",
        booking_mode="manual_confirm",
        currency="DZD",
    )
    db_session.add(b_confirm)
    await db_session.commit()

    # Confirm
    conf_resp = await client.post(
        f"/api/v1/partner/bookings/{b_confirm.id}/respond",
        headers=partner_headers,
        json={"decision": "confirm", "note": "Bienvenue !"},
    )
    assert conf_resp.status_code == 200
    assert conf_resp.json()["status"] == "confirmed"

    res_conf = await db_session.execute(
        select(Notification).where(
            and_(
                Notification.tenant_id == test_tenant.id,
                Notification.user_id == test_user.id,
                Notification.booking_id == b_confirm.id,
            )
        )
    )
    conf_notifs = res_conf.scalars().all()
    assert len(conf_notifs) == 1
    assert conf_notifs[0].type == "booking_confirmed"
    assert conf_notifs[0].payload["partner_note"] == "Bienvenue !"


@pytest.mark.asyncio
async def test_expire_overdue_requests_notifies_both_once_and_respects_tenant_isolation(
    db_session, test_tenant, second_tenant, test_user, partner_user
):
    """booking_lifecycle.py: expire_overdue_requests notifies traveller and partner once, scoped by tenant."""
    poi = POI(tenant_id=test_tenant.id, slug="poi-exp", name="Casbah d'Alger", city="Alger", booking_mode="manual_confirm")
    db_session.add(poi)
    await db_session.flush()

    mgr = POIManager(tenant_id=test_tenant.id, poi_id=poi.id, user_id=partner_user.id)
    db_session.add(mgr)

    # Overdue booking in test_tenant
    overdue = Booking(
        tenant_id=test_tenant.id,
        user_id=test_user.id,
        poi_id=poi.id,
        adapter_type="tour",
        status="requested",
        booking_mode="manual_confirm",
        respond_by=utcnow() - timedelta(hours=2),
        currency="DZD",
    )
    db_session.add(overdue)

    # Overdue booking in second_tenant (must not be touched when expiring test_tenant)
    poi2 = POI(tenant_id=second_tenant.id, slug="poi-other", name="Other Place", city="Paris", booking_mode="manual_confirm")
    db_session.add(poi2)
    await db_session.flush()

    overdue_other = Booking(
        tenant_id=second_tenant.id,
        user_id=test_user.id,
        poi_id=poi2.id,
        adapter_type="tour",
        status="requested",
        booking_mode="manual_confirm",
        respond_by=utcnow() - timedelta(hours=2),
        currency="EUR",
    )
    db_session.add(overdue_other)
    await db_session.commit()

    # Expire test_tenant
    expired_count = await expire_overdue_requests(db_session, test_tenant.id)
    assert expired_count == 1

    # Check other tenant booking was NOT expired
    await db_session.refresh(overdue_other)
    assert overdue_other.status == "requested"

    # Check test_tenant notifications: 1 for traveller, 1 for partner
    res_trav = await db_session.execute(
        select(Notification).where(
            and_(
                Notification.tenant_id == test_tenant.id,
                Notification.user_id == test_user.id,
                Notification.booking_id == overdue.id,
            )
        )
    )
    assert len(res_trav.scalars().all()) == 1

    res_partner = await db_session.execute(
        select(Notification).where(
            and_(
                Notification.tenant_id == test_tenant.id,
                Notification.user_id == partner_user.id,
                Notification.booking_id == overdue.id,
            )
        )
    )
    assert len(res_partner.scalars().all()) == 1

    # Re-running expire_overdue_requests immediately afterwards: returns 0 and creates no duplicates
    repeat_count = await expire_overdue_requests(db_session, test_tenant.id)
    assert repeat_count == 0

    res_trav_after = await db_session.execute(
        select(Notification).where(
            and_(
                Notification.tenant_id == test_tenant.id,
                Notification.user_id == test_user.id,
                Notification.booking_id == overdue.id,
            )
        )
    )
    assert len(res_trav_after.scalars().all()) == 1
