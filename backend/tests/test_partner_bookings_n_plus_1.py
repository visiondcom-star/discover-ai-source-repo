"""N+1 sur la liste des réservations partenaire (perf, backend).

`GET /partner/bookings` (`list_partner_bookings`) construisait chaque réponse
via `_to_partner_response`, qui fait 2 requêtes par réservation (nom du POI,
nom du voyageur) : 1 + 2N requêtes, jusqu'à 401 pour `limit=200`.

Le correctif charge `Booking` + `POI.name` + `User.full_name` en UNE requête
(jointures externes restreintes au tenant) puis bâtit les réponses en mémoire :
le nombre de requêtes SQL ne dépend plus de N.

Tests :
1. Constance du nombre de requêtes : 3 puis 15 réservations `requested`
   affichent le MÊME nombre de requêtes SQL (échoue sur main : +2 par ligne).
2. Équivalence : un élément de la liste est identique, champ par champ, à
   `GET /partner/bookings/{id}` (même source de vérité qu'avant).
3. Non-régression confidentialité : la liste expose `details` utiles et jamais
   de PII (même liste blanche que le détail).
"""
import pytest
from sqlalchemy import event

import app.database as db_module
from tests.test_partner_manual_confirm import (
    _consent,
    _create_booking,
    _headers_for,
    _poi,
    _user,
)


# ---- Compteur de requêtes SQL (cf. test_tenant_ai_quota_db) ------------------

class _SqlCounter:
    """Compte les statements réellement émis par le moteur de test."""

    def __init__(self):
        self.count = 0

    def _before(self, conn, cursor, statement, parameters, context, executemany):
        self.count += 1


class _CountSql:
    """Contexte : branche le compteur sur `before_cursor_execute` du moteur."""

    def __init__(self):
        self._counter = _SqlCounter()

    def __enter__(self):
        event.listen(
            db_module.engine.sync_engine,
            "before_cursor_execute",
            self._counter._before,
        )
        return self._counter

    def __exit__(self, *exc):
        event.remove(
            db_module.engine.sync_engine,
            "before_cursor_execute",
            self._counter._before,
        )
        return False


# ---- Fabrique : un POI, un partenaire rattaché, N réservations `requested` ---

async def _setup_partner_and_poi(client, db_session, tenant, slug):
    from app.models import POIManager

    poi = await _poi(db_session, tenant, slug, "manual_confirm")
    partner = await _user(db_session, tenant, f"np1-{slug}@example.com", "Partner NP1")
    db_session.add(POIManager(tenant_id=tenant.id, poi_id=poi.id, user_id=partner.id))
    await db_session.commit()
    partner_headers = await _headers_for(client, tenant, partner.email)
    traveller_headers = await _headers_for(client, tenant, "test@example.com")
    return poi, partner_headers, traveller_headers


async def _make_requested_on(client, traveller_headers, poi, i):
    created = await _create_booking(
        client,
        traveller_headers,
        poi,
        booking_data={"date": "2026-11-01", "guests": 2, "ref": f"b{i}"},
    )
    assert created.status_code == 201, created.text
    consented = await _consent(client, traveller_headers, created.json()["id"], consent=True)
    assert consented.status_code == 200, consented.text
    assert consented.json()["status"] == "requested"


# ---- 1. Nombre de requêtes indépendant de N ----------------------------------

@pytest.mark.asyncio
async def test_partner_list_query_count_is_independent_of_n(
    client, db_session, test_tenant, test_user
):
    poi, partner_headers, traveller_headers = await _setup_partner_and_poi(
        client, db_session, test_tenant, "count-poi"
    )

    async def count_list():
        with _CountSql() as counter:
            resp = await client.get("/api/v1/partner/bookings", headers=partner_headers)
        assert resp.status_code == 200, resp.text
        return counter.count, resp.json()

    for i in range(3):
        await _make_requested_on(client, traveller_headers, poi, i)
    n3, list3 = await count_list()
    assert len(list3) == 3
    # Garde-fou : le compteur doit réellement voir des requêtes, sinon un
    # débrachage du listener donnerait 0 == 0 et le test passerait à vide.
    assert n3 > 0, "le compteur SQL n'a rien vu — listener mal branché ?"

    for i in range(3, 15):
        await _make_requested_on(client, traveller_headers, poi, i)
    n15, list15 = await count_list()
    assert len(list15) == 15

    # Avant le correctif : +2 requêtes par réservation (POI + voyageur), donc
    # n15 = n3 + 24. Après : une seule requête, le compte ne bouge pas.
    assert n15 == n3, (
        f"le nombre de requêtes SQL dépend de N : {n3} (N=3) -> {n15} (N=15)"
    )


# ---- 2. Équivalence liste == détail ------------------------------------------

@pytest.mark.asyncio
async def test_partner_list_item_equals_detail_field_by_field(
    client, db_session, test_tenant, test_user
):
    poi, partner_headers, traveller_headers = await _setup_partner_and_poi(
        client, db_session, test_tenant, "equiv-poi"
    )
    await _make_requested_on(client, traveller_headers, poi, 0)

    listed = await client.get("/api/v1/partner/bookings", headers=partner_headers)
    assert listed.status_code == 200, listed.text
    assert listed.json(), "la liste doit contenir la réservation"
    booking_id = listed.json()[0]["id"]

    detail = await client.get(
        f"/api/v1/partner/bookings/{booking_id}", headers=partner_headers
    )
    assert detail.status_code == 200, detail.text

    item = next(b for b in listed.json() if b["id"] == booking_id)
    # Les champs issus des jointures doivent être RÉELLEMENT peuplés : sans ce
    # garde-fou, l'égalité tiendrait même si liste et détail renvoyaient tous
    # deux "" et None (jointure silencieusement débranchée).
    assert item["poi_name"], "la jointure POI doit ramener le nom du POI"
    assert item["traveller_name"], "la jointure User doit ramener le nom du voyageur"
    # Même source de vérité : la liste et le détail doivent coincider exactement
    # (dont poi_name, traveller_name, details — la jointure ne doit rien altérer).
    assert item == detail.json()


# ---- 3. Non-régression confidentialité sur la LISTE --------------------------

@pytest.mark.asyncio
async def test_partner_list_exposes_details_but_never_pii(
    client, db_session, test_tenant, test_user
):
    poi, partner_headers, traveller_headers = await _setup_partner_and_poi(
        client, db_session, test_tenant, "pii-list-poi"
    )
    created = await _create_booking(
        client,
        traveller_headers,
        poi,
        booking_data={
            "date": "2026-11-01",
            "party_size": 4,
            "notes": "Table près de la fenêtre",
            "email": "traveller@example.com",  # sensible
            "phone_number": "+33600000000",  # hors liste blanche
        },
    )
    assert created.status_code == 201, created.text
    await _consent(client, traveller_headers, created.json()["id"], consent=True)

    listed = await client.get("/api/v1/partner/bookings", headers=partner_headers)
    assert listed.status_code == 200, listed.text
    blob = listed.text
    assert "traveller@example.com" not in blob
    assert "+33600000000" not in blob
    details = listed.json()[0]["details"]
    assert details["date"] == "2026-11-01"
    assert details["party_size"] == 4
    assert "phone_number" not in details
    assert set(details) <= {"date", "party_size", "notes"}
