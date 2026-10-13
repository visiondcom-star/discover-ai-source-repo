"""`is_partner` sur `GET /auth/me` : le mobile sait si l'utilisateur est
partenaire (rattaché à au moins un POI du tenant via `poi_managers`).

`is_partner` n'est PAS un attribut ORM de `User` : il est dérivé à la volée par
la dépendance `get_partner_poi_ids` (déjà utilisée par les endpoints partenaire)
et injecté à la construction de la réponse. Aucune logique de rôle dupliquée.

Ces tests échouent avant le correctif (clé `is_partner` absente de
`UserResponse`) puis passent.
"""
import pytest

from tests.test_partner_manual_confirm import _headers_for, _poi


async def _attach(db_session, tenant, poi, user):
    """Rattache `user` à `poi` dans `tenant` (ligne `poi_managers`)."""
    from app.models import POIManager

    db_session.add(POIManager(tenant_id=tenant.id, poi_id=poi.id, user_id=user.id))
    await db_session.commit()


# ---- 1. Voyageur sans rattachement : is_partner false ------------------------

@pytest.mark.asyncio
async def test_me_is_partner_false_for_plain_traveller(client, test_user, test_tenant):
    headers = await _headers_for(client, test_tenant, test_user.email)
    resp = await client.get("/api/v1/auth/me", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["is_partner"] is False


# ---- 2. Utilisateur rattaché à un POI du tenant : true -----------------------

@pytest.mark.asyncio
async def test_me_is_partner_true_when_attached_to_poi(
    client, db_session, test_tenant, test_user
):
    poi = await _poi(db_session, test_tenant, "partner-me-poi", "manual_confirm")
    await _attach(db_session, test_tenant, poi, test_user)

    headers = await _headers_for(client, test_tenant, test_user.email)
    resp = await client.get("/api/v1/auth/me", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["is_partner"] is True


# ---- 3. Admin sans rattachement : is_admin true ET is_partner false ----------

@pytest.mark.asyncio
async def test_me_admin_without_attachment_is_not_partner(client, admin_headers):
    # Le droit « secours » admin reste porté par `is_admin`, jamais par
    # `is_partner` : un admin non rattaché n'est pas partenaire.
    resp = await client.get("/api/v1/auth/me", headers=admin_headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["is_admin"] is True
    assert data["is_partner"] is False


# ---- 4. Rattachement dans un AUTRE tenant : false (isolation) ----------------

@pytest.mark.asyncio
async def test_me_attachment_in_other_tenant_is_not_partner(
    client, db_session, test_tenant, test_user, other_tenant
):
    # L'utilisateur appartient à `test-tenant` ; la seule ligne `poi_managers` le
    # rattache à un POI d'`other-tenant`. `get_partner_poi_ids` filtre par le
    # tenant de l'utilisateur => ce rattachement étranger ne compte pas.
    foreign_poi = await _poi(db_session, other_tenant, "foreign-poi", "manual_confirm")
    await _attach(db_session, other_tenant, foreign_poi, test_user)

    headers = await _headers_for(client, test_tenant, test_user.email)
    resp = await client.get("/api/v1/auth/me", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["is_partner"] is False
