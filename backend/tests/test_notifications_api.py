"""Tests for the notifications API endpoints: list, mark all read, mark one read, pagination, isolation."""
import uuid
import pytest
from sqlalchemy import select

from app.models import Notification, Tenant, User, POI, Booking
from app.core.security import create_access_token, get_password_hash


@pytest.fixture
async def user_a(db_session, test_tenant):
    user = User(
        tenant_id=test_tenant.id,
        email="user_a@example.com",
        hashed_password=get_password_hash("pass123"),
        full_name="User Alpha",
        locale="fr",
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


@pytest.fixture
async def user_b(db_session, test_tenant):
    user = User(
        tenant_id=test_tenant.id,
        email="user_b@example.com",
        hashed_password=get_password_hash("pass123"),
        full_name="User Bravo",
        locale="en",
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


@pytest.fixture
async def tenant_2(db_session):
    t = Tenant(
        slug="tenant-two",
        name="Tenant Two",
        default_language="en",
        default_currency="USD",
    )
    db_session.add(t)
    await db_session.commit()
    await db_session.refresh(t)
    return t


@pytest.fixture
async def user_other_tenant(db_session, tenant_2):
    user = User(
        tenant_id=tenant_2.id,
        email="other@example.com",
        hashed_password=get_password_hash("pass123"),
        full_name="Other User",
        locale="en",
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


def _auth_headers_for(user: User, tenant_slug: str):
    token = create_access_token(data={"sub": str(user.id), "email": user.email, "tenant": tenant_slug})
    return {"Authorization": f"Bearer {token}", "X-Tenant-Slug": tenant_slug}


@pytest.mark.asyncio
async def test_notifications_isolation_between_users(client, test_tenant, user_a, user_b, db_session):
    """User A should only see their own notifications, not User B's."""
    n_a = Notification(
        tenant_id=test_tenant.id,
        user_id=user_a.id,
        type="booking_confirmed",
        payload={"poi_name": "Site A"},
        locale="fr",
    )
    n_b = Notification(
        tenant_id=test_tenant.id,
        user_id=user_b.id,
        type="booking_declined",
        payload={"poi_name": "Site B"},
        locale="en",
    )
    db_session.add_all([n_a, n_b])
    await db_session.commit()

    headers_a = _auth_headers_for(user_a, test_tenant.slug)
    resp_a = await client.get("/api/v1/context/notifications", headers=headers_a)
    assert resp_a.status_code == 200
    data_a = resp_a.json()
    assert len(data_a["notifications"]) == 1
    assert data_a["notifications"][0]["id"] == str(n_a.id)
    assert data_a["notifications"][0]["type"] == "booking_confirmed"
    assert data_a["unread_count"] == 1

    headers_b = _auth_headers_for(user_b, test_tenant.slug)
    resp_b = await client.get("/api/v1/context/notifications", headers=headers_b)
    assert resp_b.status_code == 200
    data_b = resp_b.json()
    assert len(data_b["notifications"]) == 1
    assert data_b["notifications"][0]["id"] == str(n_b.id)
    assert data_b["notifications"][0]["type"] == "booking_declined"


@pytest.mark.asyncio
async def test_notifications_isolation_between_tenants(client, test_tenant, tenant_2, user_a, user_other_tenant, db_session):
    """Notifications from tenant 2 are completely invisible to tenant 1."""
    n1 = Notification(
        tenant_id=test_tenant.id,
        user_id=user_a.id,
        type="booking_confirmed",
        payload={"poi_name": "Tenant 1 Place"},
        locale="fr",
    )
    n2 = Notification(
        tenant_id=tenant_2.id,
        user_id=user_other_tenant.id,
        type="booking_confirmed",
        payload={"poi_name": "Tenant 2 Place"},
        locale="en",
    )
    db_session.add_all([n1, n2])
    await db_session.commit()

    headers_1 = _auth_headers_for(user_a, test_tenant.slug)
    resp_1 = await client.get("/api/v1/context/notifications", headers=headers_1)
    assert resp_1.status_code == 200
    ids_1 = [n["id"] for n in resp_1.json()["notifications"]]
    assert str(n1.id) in ids_1
    assert str(n2.id) not in ids_1

    headers_2 = _auth_headers_for(user_other_tenant, tenant_2.slug)
    resp_2 = await client.get("/api/v1/context/notifications", headers=headers_2)
    assert resp_2.status_code == 200
    ids_2 = [n["id"] for n in resp_2.json()["notifications"]]
    assert str(n2.id) in ids_2
    assert str(n1.id) not in ids_2


@pytest.mark.asyncio
async def test_notifications_pagination_and_ordering(client, test_tenant, user_a, db_session):
    """Pagination (limit, offset) and recent-first sorting."""
    for i in range(5):
        n = Notification(
            tenant_id=test_tenant.id,
            user_id=user_a.id,
            type="booking_confirmed",
            payload={"index": i},
            locale="fr",
        )
        db_session.add(n)
    await db_session.commit()

    headers = _auth_headers_for(user_a, test_tenant.slug)

    # Page 1: limit 2, offset 0
    p1 = await client.get("/api/v1/context/notifications?limit=2&offset=0", headers=headers)
    assert p1.status_code == 200
    data_p1 = p1.json()
    assert len(data_p1["notifications"]) == 2
    assert data_p1["total"] == 2
    assert data_p1["unread_count"] == 5

    # Page 2: limit 2, offset 2
    p2 = await client.get("/api/v1/context/notifications?limit=2&offset=2", headers=headers)
    assert p2.status_code == 200
    data_p2 = p2.json()
    assert len(data_p2["notifications"]) == 2
    # Disjoint IDs
    p1_ids = {n["id"] for n in data_p1["notifications"]}
    p2_ids = {n["id"] for n in data_p2["notifications"]}
    assert p1_ids.isdisjoint(p2_ids)


@pytest.mark.asyncio
async def test_mark_single_notification_read(client, test_tenant, user_a, user_b, db_session):
    """POST /notifications/{id}/read marks a notification as read and returns 404 for other users."""
    n = Notification(
        tenant_id=test_tenant.id,
        user_id=user_a.id,
        type="booking_confirmed",
        payload={"poi_name": "Test"},
        locale="fr",
    )
    db_session.add(n)
    await db_session.commit()

    headers_b = _auth_headers_for(user_b, test_tenant.slug)
    # User B cannot mark User A's notification as read
    resp_b = await client.post(f"/api/v1/context/notifications/{n.id}/read", headers=headers_b)
    assert resp_b.status_code == 404

    # User A marks as read
    headers_a = _auth_headers_for(user_a, test_tenant.slug)
    resp_a = await client.post(f"/api/v1/context/notifications/{n.id}/read", headers=headers_a)
    assert resp_a.status_code == 200
    assert resp_a.json()["read"] is True
    assert resp_a.json()["read_at"] is not None

    # Verify unread_count drops to 0
    list_resp = await client.get("/api/v1/context/notifications", headers=headers_a)
    assert list_resp.json()["unread_count"] == 0
    assert list_resp.json()["notifications"][0]["read"] is True


@pytest.mark.asyncio
async def test_mark_all_read_real_count(client, test_tenant, user_a, db_session):
    """POST /notifications/read-all marks all unread notifications of user and returns actual count."""
    for i in range(3):
        n = Notification(
            tenant_id=test_tenant.id,
            user_id=user_a.id,
            type="booking_confirmed",
            payload={"i": i},
            locale="fr",
        )
        db_session.add(n)
    await db_session.commit()

    headers = _auth_headers_for(user_a, test_tenant.slug)
    resp = await client.post("/api/v1/context/notifications/read-all", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["marked_as_read"] == 3

    # Subsequent call returns 0
    resp_again = await client.post("/api/v1/context/notifications/read-all", headers=headers)
    assert resp_again.json()["marked_as_read"] == 0
