"""Modes de réservation par POI + création idempotente."""
import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError


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


async def _count(db_session, tenant):
    from app.models import Booking

    r = await db_session.execute(
        select(func.count()).select_from(Booking).where(Booking.tenant_id == tenant.id)
    )
    return r.scalar_one()


def _payload(poi, **extra):
    body = {"poi_id": str(poi.id), "adapter_type": "tour", "booking_data": {"date": "2026-11-01"}}
    body.update(extra)
    return body


@pytest.mark.asyncio
async def test_info_only_poi_cannot_be_booked(client, auth_headers, db_session, test_tenant):
    poi = await _poi(db_session, test_tenant, "info-only-poi", "info_only")
    r = await client.post("/api/v1/bookings/", headers=auth_headers, json=_payload(poi))
    assert r.status_code == 422
    assert await _count(db_session, test_tenant) == 0


@pytest.mark.asyncio
async def test_unsupported_mode_is_rejected_defensively(client, auth_headers, db_session, test_tenant):
    poi = await _poi(db_session, test_tenant, "deposit-poi", "deposit")
    r = await client.post("/api/v1/bookings/", headers=auth_headers, json=_payload(poi))
    assert r.status_code == 422


@pytest.mark.asyncio
async def test_booking_freezes_mode_and_sets_sla_only_for_manual_confirm(
    client, auth_headers, db_session, test_tenant
):
    manual = await _poi(db_session, test_tenant, "manual-poi", "manual_confirm")
    plain = await _poi(db_session, test_tenant, "request-poi", "request")

    r1 = await client.post("/api/v1/bookings/", headers=auth_headers, json=_payload(manual))
    r2 = await client.post("/api/v1/bookings/", headers=auth_headers, json=_payload(plain))
    assert r1.status_code == r2.status_code == 201
    assert r1.json()["booking_mode"] == "manual_confirm"
    assert r1.json()["respond_by"] is not None
    assert r2.json()["booking_mode"] == "request"
    assert r2.json()["respond_by"] is None

    # Changer le mode du POI ensuite n'affecte pas la réservation existante.
    manual.booking_mode = "pay_on_site"
    await db_session.commit()
    again = await client.get(f"/api/v1/bookings/{r1.json()['id']}", headers=auth_headers)
    assert again.json()["booking_mode"] == "manual_confirm"


@pytest.mark.asyncio
async def test_same_key_same_request_replays_without_duplicate(client, auth_headers, db_session, test_tenant):
    poi = await _poi(db_session, test_tenant, "idem-poi")
    headers = {**auth_headers, "Idempotency-Key": "idem-key-0001"}

    first = await client.post("/api/v1/bookings/", headers=headers, json=_payload(poi))
    second = await client.post("/api/v1/bookings/", headers=headers, json=_payload(poi))

    assert first.status_code == 201
    assert second.status_code == 200
    assert second.json()["id"] == first.json()["id"]
    assert await _count(db_session, test_tenant) == 1


@pytest.mark.asyncio
async def test_json_key_order_does_not_change_the_request_hash(client, auth_headers, db_session, test_tenant):
    poi = await _poi(db_session, test_tenant, "order-poi")
    headers = {**auth_headers, "Idempotency-Key": "idem-key-order"}
    a = {"poi_id": str(poi.id), "adapter_type": "tour", "booking_data": {"a": 1, "b": 2}}
    b = {"booking_data": {"b": 2, "a": 1}, "adapter_type": "tour", "poi_id": str(poi.id)}

    first = await client.post("/api/v1/bookings/", headers=headers, json=a)
    second = await client.post("/api/v1/bookings/", headers=headers, json=b)
    assert first.status_code == 201 and second.status_code == 200


@pytest.mark.asyncio
async def test_same_key_different_request_conflicts(client, auth_headers, db_session, test_tenant):
    poi = await _poi(db_session, test_tenant, "conflict-poi")
    headers = {**auth_headers, "Idempotency-Key": "idem-key-0002"}

    first = await client.post("/api/v1/bookings/", headers=headers, json=_payload(poi))
    other = _payload(poi, booking_data={"date": "2026-12-24"})
    second = await client.post("/api/v1/bookings/", headers=headers, json=other)

    assert first.status_code == 201
    assert second.status_code == 409
    assert await _count(db_session, test_tenant) == 1


@pytest.mark.asyncio
async def test_without_key_each_request_creates_a_booking(client, auth_headers, db_session, test_tenant):
    poi = await _poi(db_session, test_tenant, "nokey-poi")
    r1 = await client.post("/api/v1/bookings/", headers=auth_headers, json=_payload(poi))
    r2 = await client.post("/api/v1/bookings/", headers=auth_headers, json=_payload(poi))
    assert r1.status_code == r2.status_code == 201
    assert r1.json()["id"] != r2.json()["id"]


@pytest.mark.asyncio
async def test_too_short_key_is_rejected(client, auth_headers, db_session, test_tenant):
    poi = await _poi(db_session, test_tenant, "short-key-poi")
    headers = {**auth_headers, "Idempotency-Key": "abc"}
    r = await client.post("/api/v1/bookings/", headers=headers, json=_payload(poi))
    assert r.status_code == 422


@pytest.mark.asyncio
async def test_race_loser_falls_back_to_replay(client, auth_headers, db_session, test_tenant, monkeypatch):
    """Simule deux requêtes simultanées : la 1re lecture ne voit rien (la gagnante n'est pas
    encore commitée), l'INSERT échoue sur la contrainte unique, la perdante rejoue."""
    from app.api.v1.endpoints import bookings as mod

    poi = await _poi(db_session, test_tenant, "race-poi")
    headers = {**auth_headers, "Idempotency-Key": "idem-key-race"}
    winner = await client.post("/api/v1/bookings/", headers=headers, json=_payload(poi))
    assert winner.status_code == 201

    real = mod._find_by_key
    calls = {"n": 0}

    async def blind_first_time(*args, **kwargs):
        calls["n"] += 1
        return None if calls["n"] == 1 else await real(*args, **kwargs)

    monkeypatch.setattr(mod, "_find_by_key", blind_first_time)
    loser = await client.post("/api/v1/bookings/", headers=headers, json=_payload(poi))

    assert loser.status_code == 200
    assert loser.json()["id"] == winner.json()["id"]
    assert await _count(db_session, test_tenant) == 1


@pytest.mark.asyncio
async def test_unique_constraint_exists_at_database_level(db_session, test_tenant, test_user):
    from app.models import Booking

    poi = await _poi(db_session, test_tenant, "db-unique-poi")
    for _ in range(2):
        db_session.add(
            Booking(
                tenant_id=test_tenant.id, user_id=test_user.id, poi_id=poi.id,
                adapter_type="tour", status="pending", currency="DZD",
                idempotency_key="db-level-key", request_hash="x",
            )
        )
    with pytest.raises(IntegrityError):
        await db_session.commit()
    await db_session.rollback()


def test_poi_schema_rejects_unsupported_modes():
    from pydantic import ValidationError
    from app.schemas import POICreate

    base = {"name": "Test place", "city": "Alger", "categories": ["culture"]}
    assert POICreate(**base).booking_mode == "request"
    assert POICreate(**base, booking_mode="info_only").booking_mode == "info_only"
    with pytest.raises(ValidationError):
        POICreate(**base, booking_mode="deposit")
    with pytest.raises(ValidationError):
        POICreate(**base, booking_mode="nonsense")


