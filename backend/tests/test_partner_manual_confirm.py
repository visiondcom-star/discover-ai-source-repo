"""Rôle partenaire + réponse aux réservations manual_confirm (0013)."""
import asyncio

import pytest


# ---- Fabrique d'objets ------------------------------------------------------

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


async def _user(db_session, tenant, email, full_name, is_admin=False):
    from app.models import User
    from app.core.security import get_password_hash

    user = User(
        tenant_id=tenant.id,
        email=email,
        hashed_password=get_password_hash("testpass123"),
        full_name=full_name,
        is_active=True,
        is_admin=is_admin,
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


async def _headers_for(client, tenant, email, password="testpass123"):
    login = await client.post(
        "/api/v1/auth/login",
        headers={"X-Tenant-Slug": tenant.slug},
        json={"email": email, "password": password},
    )
    assert login.status_code == 200, login.text
    token = login.json()["access_token"]
    return {"Authorization": f"Bearer {token}", "X-Tenant-Slug": tenant.slug}


async def _create_booking(client, headers, poi, adapter_type="tour", booking_data=None):
    return await client.post(
        "/api/v1/bookings/",
        headers=headers,
        json={
            "poi_id": str(poi.id),
            "adapter_type": adapter_type,
            "booking_data": booking_data or {"date": "2026-11-01"},
        },
    )


async def _consent(client, headers, booking_id, consent=True):
    return await client.post(
        f"/api/v1/bookings/{booking_id}/consent",
        headers=headers,
        json={"consent": consent},
    )


async def _make_requested(client, db_session, tenant, user, slug, mode="manual_confirm"):
    """Crée un POI + une réservation passée en `requested` (voyageur=user)."""
    poi = await _poi(db_session, tenant, slug, mode)
    headers = await _headers_for(client, tenant, user.email)
    created = await _create_booking(client, headers, poi)
    assert created.status_code == 201, created.text
    consented = await _consent(client, headers, created.json()["id"], consent=True)
    assert consented.status_code == 200, consented.text
    return poi, created.json(), consented.json()



# ---- 1-2. Consentement : manual_confirm => requested, autres => confirmed ---

@pytest.mark.asyncio
async def test_manual_confirm_consent_goes_to_requested(client, db_session, test_tenant, test_user):
    poi, created, consented = await _make_requested(
        client, db_session, test_tenant, test_user, "manual-consent-poi", "manual_confirm"
    )
    assert consented["status"] == "requested"
    assert consented["external_id"] is None
    assert consented["respond_by"] is not None


@pytest.mark.asyncio
async def test_request_mode_consent_confirms_immediately(client, db_session, test_tenant, test_user):
    # Non-régression : le mode `request` confirme tout de suite (flux historique).
    poi, created, consented = await _make_requested(
        client, db_session, test_tenant, test_user, "request-consent-poi", "request"
    )
    assert consented["status"] == "confirmed"
    assert consented["external_id"] is not None


# ---- 3-5. Autorisation & isolation tenant -----------------------------------

@pytest.mark.asyncio
async def test_attached_partner_sees_request_and_unattached_gets_403(
    client, db_session, test_tenant, test_user
):
    from app.models import POIManager

    poi, created, _ = await _make_requested(
        client, db_session, test_tenant, test_user, "attach-poi", "manual_confirm"
    )
    partner = await _user(db_session, test_tenant, "partner1@example.com", "Partner One")
    stranger = await _user(db_session, test_tenant, "stranger@example.com", "Stranger")

    db_session.add(POIManager(tenant_id=test_tenant.id, poi_id=poi.id, user_id=partner.id))
    await db_session.commit()

    partner_headers = await _headers_for(client, test_tenant, partner.email)
    stranger_headers = await _headers_for(client, test_tenant, stranger.email)

    listed = await client.get("/api/v1/partner/bookings", headers=partner_headers)
    assert listed.status_code == 200
    assert any(b["id"] == created["id"] for b in listed.json())

    denied = await client.get("/api/v1/partner/bookings", headers=stranger_headers)
    assert denied.status_code == 403


@pytest.mark.asyncio
async def test_partner_of_another_poi_gets_404(client, db_session, test_tenant, test_user):
    from app.models import POIManager

    poi, created, _ = await _make_requested(
        client, db_session, test_tenant, test_user, "other-manager-poi", "manual_confirm"
    )
    other_poi = await _poi(db_session, test_tenant, "other-manager-other-poi", "manual_confirm")
    partner = await _user(db_session, test_tenant, "p2@example.com", "Partner Two")
    # Rattaché à l'AUTRE poi, pas à celui de la réservation.
    db_session.add(POIManager(tenant_id=test_tenant.id, poi_id=other_poi.id, user_id=partner.id))
    await db_session.commit()
    headers = await _headers_for(client, test_tenant, partner.email)

    resp = await client.post(
        f"/api/v1/partner/bookings/{created['id']}/respond",
        headers=headers,
        json={"decision": "confirm"},
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_cross_tenant_respond_is_404(client, db_session, test_tenant, test_user, other_tenant, other_admin):
    poi, created, _ = await _make_requested(
        client, db_session, test_tenant, test_user, "cross-tenant-poi", "manual_confirm"
    )
    # Admin de l'AUTRE tenant tente de répondre sur cette réservation => 404.
    login = await client.post(
        "/api/v1/auth/login",
        headers={"X-Tenant-Slug": other_tenant.slug},
        json={"email": other_admin.email, "password": "otheradminpass123"},
    )
    headers = {
        "Authorization": f"Bearer {login.json()['access_token']}",
        "X-Tenant-Slug": other_tenant.slug,
    }
    resp = await client.post(
        f"/api/v1/partner/bookings/{created['id']}/respond",
        headers=headers,
        json={"decision": "confirm"},
    )
    assert resp.status_code == 404


# ---- 6-8. Réponse partenaire : confirm / decline / idempotence --------------

async def _attached_partner_headers(client, db_session, tenant, poi, email="boss@example.com", name="Boss"):
    from app.models import POIManager

    partner = await _user(db_session, tenant, email, name)
    db_session.add(POIManager(tenant_id=tenant.id, poi_id=poi.id, user_id=partner.id))
    await db_session.commit()
    return partner, await _headers_for(client, tenant, email)


@pytest.mark.asyncio
async def test_confirm_sets_confirmed_and_traveller_sees_it(client, db_session, test_tenant, test_user):
    poi, created, _ = await _make_requested(
        client, db_session, test_tenant, test_user, "confirm-poi", "manual_confirm"
    )
    partner, headers = await _attached_partner_headers(client, db_session, test_tenant, poi)

    resp = await client.post(
        f"/api/v1/partner/bookings/{created['id']}/respond",
        headers=headers,
        json={"decision": "confirm"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "confirmed"
    assert body["external_id"]
    assert body["responded_at"]

    traveller = await _headers_for(client, test_tenant, test_user.email)
    seen = await client.get(f"/api/v1/bookings/{created['id']}", headers=traveller)
    assert seen.json()["status"] == "confirmed"


@pytest.mark.asyncio
async def test_decline_with_note_is_visible_to_traveller(client, db_session, test_tenant, test_user):
    poi, created, _ = await _make_requested(
        client, db_session, test_tenant, test_user, "decline-poi", "manual_confirm"
    )
    partner, headers = await _attached_partner_headers(client, db_session, test_tenant, poi, "d@x.com", "Decliner")

    resp = await client.post(
        f"/api/v1/partner/bookings/{created['id']}/respond",
        headers=headers,
        json={"decision": "decline", "note": "Complet ce jour-là."},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "declined"
    assert resp.json()["partner_note"] == "Complet ce jour-là."

    traveller = await _headers_for(client, test_tenant, test_user.email)
    seen = await client.get(f"/api/v1/bookings/{created['id']}", headers=traveller)
    assert seen.json()["partner_note"] == "Complet ce jour-là."


@pytest.mark.asyncio
async def test_same_decision_replay_is_idempotent_and_opposite_conflicts(
    client, db_session, test_tenant, test_user
):
    poi, created, _ = await _make_requested(
        client, db_session, test_tenant, test_user, "idem-poi", "manual_confirm"
    )
    partner, headers = await _attached_partner_headers(client, db_session, test_tenant, poi)

    first = await client.post(
        f"/api/v1/partner/bookings/{created['id']}/respond", headers=headers, json={"decision": "confirm"}
    )
    assert first.status_code == 200

    replay = await client.post(
        f"/api/v1/partner/bookings/{created['id']}/respond", headers=headers, json={"decision": "confirm"}
    )
    assert replay.status_code == 200
    assert replay.json()["status"] == "confirmed"

    opposite = await client.post(
        f"/api/v1/partner/bookings/{created['id']}/respond", headers=headers, json={"decision": "decline"}
    )
    assert opposite.status_code == 409


# ---- 9. Expiration paresseuse -----------------------------------------------

@pytest.mark.asyncio
async def test_overdue_request_expires_and_cannot_be_answered(
    client, db_session, test_tenant, test_user
):
    from datetime import timedelta
    import sqlalchemy
    from app.models import Booking, utcnow

    poi, created, _ = await _make_requested(
        client, db_session, test_tenant, test_user, "expire-poi", "manual_confirm"
    )
    partner, headers = await _attached_partner_headers(client, db_session, test_tenant, poi)

    # Rétrograde l'échéance dans le passé pour forcer l'expiration.
    result = await db_session.execute(
        sqlalchemy.select(Booking).where(Booking.id == created["id"])
    )
    booking = result.scalar_one()
    booking.respond_by = utcnow() - timedelta(hours=1)
    await db_session.commit()

    traveller = await _headers_for(client, test_tenant, test_user.email)
    seen = await client.get(f"/api/v1/bookings/{created['id']}", headers=traveller)
    assert seen.json()["status"] == "expired"

    resp = await client.post(
        f"/api/v1/partner/bookings/{created['id']}/respond", headers=headers, json={"decision": "confirm"}
    )
    assert resp.status_code == 409


# ---- 10. Annulation voyageur d'une demande requested ------------------------

@pytest.mark.asyncio
async def test_traveller_cancel_then_partner_respond_conflicts(
    client, db_session, test_tenant, test_user
):
    poi, created, _ = await _make_requested(
        client, db_session, test_tenant, test_user, "cancel-poi", "manual_confirm"
    )
    partner, headers = await _attached_partner_headers(client, db_session, test_tenant, poi)

    traveller = await _headers_for(client, test_tenant, test_user.email)
    cancelled = await client.post(f"/api/v1/bookings/{created['id']}/cancel", headers=traveller)
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == "cancelled"

    resp = await client.post(
        f"/api/v1/partner/bookings/{created['id']}/respond", headers=headers, json={"decision": "confirm"}
    )
    assert resp.status_code == 409


# ---- 11. Admin répond sans être rattaché ------------------------------------

@pytest.mark.asyncio
async def test_admin_can_respond_without_attachment(client, db_session, test_tenant, test_user):
    poi, created, _ = await _make_requested(
        client, db_session, test_tenant, test_user, "admin-rescue-poi", "manual_confirm"
    )
    # Admin du même tenant, sans aucun rattachement POI.
    admin = await _user(db_session, test_tenant, "tenant-admin@example.com", "Tenant Admin", is_admin=True)
    admin_headers = await _headers_for(client, test_tenant, admin.email)

    resp = await client.post(
        f"/api/v1/partner/bookings/{created['id']}/respond",
        headers=admin_headers,
        json={"decision": "confirm"},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "confirmed"


# ---- 12. Rattachements admin -------------------------------------------------

@pytest.mark.asyncio
async def test_manager_attach_list_delete(client, db_session, test_tenant, test_user, other_admin):
    import sqlalchemy
    from app.models import POIManager

    poi = await _poi(db_session, test_tenant, "mgr-poi", "manual_confirm")
    admin = await _user(db_session, test_tenant, "mgr-admin@example.com", "Mgr Admin", is_admin=True)
    partner = await _user(db_session, test_tenant, "mgr-user@example.com", "Mgr User")
    non_admin = await _user(db_session, test_tenant, "mgr-nonadmin@example.com", "Non Admin")
    admin_headers = await _headers_for(client, test_tenant, admin.email)
    non_admin_headers = await _headers_for(client, test_tenant, non_admin.email)

    url = f"/api/v1/partner/pois/{poi.id}/managers"

    # Non-admin => 403
    forbidden = await client.post(url, headers=non_admin_headers, json={"user_id": str(partner.id)})
    assert forbidden.status_code == 403

    # Création => 201
    created = await client.post(url, headers=admin_headers, json={"user_id": str(partner.id)})
    assert created.status_code == 201

    # Doublon => 200, une seule ligne
    dup = await client.post(url, headers=admin_headers, json={"user_id": str(partner.id)})
    assert dup.status_code == 200
    count = (await db_session.execute(
        sqlalchemy.select(sqlalchemy.func.count()).select_from(POIManager).where(POIManager.poi_id == poi.id)
    )).scalar_one()
    assert count == 1

    # Liste contient le rattachement
    listed = await client.get(url, headers=admin_headers)
    assert listed.status_code == 200
    assert any(m["user_id"] == str(partner.id) for m in listed.json())

    # user_id d'un autre tenant => 404 : on rattache other_admin (tenant B).
    other_resp = await client.post(
        url, headers=admin_headers, json={"user_id": str(other_admin.id)}
    )
    assert other_resp.status_code == 404

    # DELETE => 204 puis absent de la liste
    deleted = await client.delete(f"{url}/{partner.id}", headers=admin_headers)
    assert deleted.status_code == 204
    listed2 = await client.get(url, headers=admin_headers)
    assert all(m["user_id"] != str(partner.id) for m in listed2.json())


# ---- 13. Concurrence : confirm / decline simultanés --------------------------

@pytest.mark.asyncio
async def test_concurrent_opposite_decisions_one_wins(client, db_session, test_tenant, test_user):
    from app.models import POIManager

    poi, created, _ = await _make_requested(
        client, db_session, test_tenant, test_user, "race-poi", "manual_confirm"
    )
    # Deux partenaires distincts rattachés au même POI.
    p1 = await _user(db_session, test_tenant, "racer1@example.com", "Racer One")
    p2 = await _user(db_session, test_tenant, "racer2@example.com", "Racer Two")
    db_session.add(POIManager(tenant_id=test_tenant.id, poi_id=poi.id, user_id=p1.id))
    db_session.add(POIManager(tenant_id=test_tenant.id, poi_id=poi.id, user_id=p2.id))
    await db_session.commit()
    h1 = await _headers_for(client, test_tenant, p1.email)
    h2 = await _headers_for(client, test_tenant, p2.email)
    booking_id = created["id"]

    confirm_task = client.post(
        f"/api/v1/partner/bookings/{booking_id}/respond", headers=h1, json={"decision": "confirm"}
    )
    decline_task = client.post(
        f"/api/v1/partner/bookings/{booking_id}/respond", headers=h2, json={"decision": "decline"}
    )
    r1, r2 = await asyncio.gather(confirm_task, decline_task)

    codes = {r1.status_code, r2.status_code}
    # Exactement un gagne (200), l'autre est 409. Jamais deux 200.
    assert 200 in codes and codes <= {200, 409}, codes
    winners = [r for r in (r1, r2) if r.status_code == 200]
    assert len(winners) == 1

    traveller = await _headers_for(client, test_tenant, test_user.email)
    final = (await client.get(f"/api/v1/bookings/{booking_id}", headers=traveller)).json()
    assert final["status"] in ("confirmed", "declined")


# ---- 14. Confidentialité : pas d'email ni de mot de passe --------------------

@pytest.mark.asyncio
async def test_partner_response_hides_email_and_password(client, db_session, test_tenant, test_user):
    poi, created, _ = await _make_requested(
        client, db_session, test_tenant, test_user, "privacy-poi", "manual_confirm"
    )
    partner, headers = await _attached_partner_headers(client, db_session, test_tenant, poi, "priv@x.com", "Priv")

    resp = await client.post(
        f"/api/v1/partner/bookings/{created['id']}/respond", headers=headers, json={"decision": "confirm"}
    )
    assert resp.status_code == 200
    blob = resp.text
    assert "email" not in blob
    assert "hashed_password" not in blob
    # Le nom du voyageur, lui, est bien exposé.
    assert resp.json()["traveller_name"] == test_user.full_name


@pytest.mark.asyncio
async def test_partner_sees_needed_details_but_never_pii(
    client, db_session, test_tenant, test_user
):
    """Le partenaire DOIT voir les détails utiles à la décision (date, nombre de
    personnes, remarques) — sinon il ne peut pas répondre — mais JAMAIS de
    donnée sensible (email, téléphone, pièce d'identité) que l'app aurait pu
    déposer dans `booking_data`.

    Contrat (§3.3) : `details` est peuplé avec `booking_data` UNIQUEMENT pour le
    partenaire/admin, et il ne doit contenir que des informations de réservation
    non sensibles. On vérifie les deux bornes : utile visible, sensible absente.
    """
    from app.models import Booking

    poi, created, _ = await _make_requested(
        client, db_session, test_tenant, test_user, "details-poi", "manual_confirm"
    )
    # booking_data réaliste incluant une donnée sensible (ce que l'app mobile ne
    # devrait PAS envoyer) pour vérifier que le contrat « pas d'email » tient
    # même si elle est présente en base.
    booking = await db_session.get(Booking, created["id"])
    booking.booking_data = {
        "date": "2026-11-01",
        "party_size": 4,
        "notes": "Table près de la fenêtre",
        "email": "traveller@example.com",  # sensible : ne doit jamais fuiter
        "phone_number": "+33600000000",  # clé inconnue : écartée par la liste blanche
        "contact_email": "contact@example.com",  # idem
    }
    await db_session.commit()

    _, headers = await _attached_partner_headers(
        client, db_session, test_tenant, poi, "details-partner@example.com", "Details Partner"
    )

    detail = await client.get(f"/api/v1/partner/bookings/{created['id']}", headers=headers)
    assert detail.status_code == 200
    details = detail.json()["details"]

    # Utile : le partenaire peut décider.
    assert details["date"] == "2026-11-01"
    assert details["party_size"] == 4
    assert details["notes"] == "Table près de la fenêtre"

    # Liste blanche : les clés non prévues n'apparaissent jamais.
    assert "phone_number" not in details
    assert "contact_email" not in details
    assert set(details) <= {"date", "party_size", "notes"}
    # Sensible : jamais exposé, même présent en base.
    assert "email" not in details


# ---- 15. Schéma PartnerRespond -----------------------------------------------

def test_partner_respond_schema_rejects_bad_decision_and_long_note():
    from pydantic import ValidationError
    from app.schemas import PartnerRespond

    with pytest.raises(ValidationError):
        PartnerRespond(decision="maybe")
    with pytest.raises(ValidationError):
        PartnerRespond(decision="confirm", note="x" * 501)
    # Cas valides
    assert PartnerRespond(decision="confirm").note is None
    assert PartnerRespond(decision="decline", note="ok").note == "ok"

