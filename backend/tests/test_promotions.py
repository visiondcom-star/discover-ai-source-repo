"""Tests des bannières promotionnelles (app/api/v1/endpoints/promotions.py).

Les écritures utilisent `admin_headers` / `other_admin_headers` : ces tests
restent valables si la gestion des promotions est un jour réservée aux admins.

Hypothèse à vérifier contre app/schemas.py : PromotionCreate n'exige que
`title` et `image_url` (colonnes non nulles du modèle).
"""
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from app.models import Promotion

URL = "/api/v1/promotions/"
BASE_HEADERS = {"X-Tenant-Slug": "test-tenant"}
OTHER_HEADERS = {"X-Tenant-Slug": "other-tenant"}


def _payload(**overrides):
    return {
        "title": "Promo",
        "image_url": "https://example.org/banner.png",
        **overrides,
    }


def _naive_utc_iso(**delta):
    """Datetime UTC naïve en ISO, comme les colonnes DateTime du modèle."""
    moment = datetime.now(timezone.utc) + timedelta(**delta)
    return moment.replace(tzinfo=None).isoformat()


async def _create(client, headers, **overrides):
    response = await client.post(URL, headers=headers, json=_payload(**overrides))
    assert response.status_code == 201, response.text
    return response.json()


async def _titles(client, headers):
    response = await client.get(URL, headers=headers)
    assert response.status_code == 200, response.text
    return [item["title"] for item in response.json()["items"]]


# ------------------------------------------------------------------ liste


async def test_list_is_public_and_empty_by_default(client, test_tenant):
    response = await client.get(URL, headers=BASE_HEADERS)
    assert response.status_code == 200
    assert response.json() == {"items": [], "total": 0}


async def test_list_works_without_trailing_slash(client, test_tenant):
    # Route enregistrée avec et sans « / » : pas de redirection 307.
    response = await client.get("/api/v1/promotions", headers=BASE_HEADERS)
    assert response.status_code == 200


async def test_list_orders_by_priority_desc(client, admin_headers):
    await _create(client, admin_headers, title="Basse", priority=1)
    await _create(client, admin_headers, title="Haute", priority=5)
    await _create(client, admin_headers, title="Moyenne", priority=3)

    assert await _titles(client, BASE_HEADERS) == ["Haute", "Moyenne", "Basse"]


async def test_list_filters_scheduling_window(client, admin_headers):
    await _create(client, admin_headers, title="Toujours")
    await _create(client, admin_headers, title="Future", starts_at=_naive_utc_iso(days=1))
    await _create(client, admin_headers, title="Expirée", ends_at=_naive_utc_iso(days=-1))
    await _create(
        client,
        admin_headers,
        title="En cours",
        starts_at=_naive_utc_iso(days=-1),
        ends_at=_naive_utc_iso(days=1),
    )

    response = await client.get(URL, headers=BASE_HEADERS)
    data = response.json()
    assert {item["title"] for item in data["items"]} == {"Toujours", "En cours"}
    assert data["total"] == 2


# --------------------------------------------------------------- création


async def test_create_promotion_returns_201(client, admin_headers):
    data = await _create(client, admin_headers, title="Été à Tipaza")
    assert data["title"] == "Été à Tipaza"
    assert data["image_url"] == "https://example.org/banner.png"
    assert data["is_active"] is True
    assert "id" in data


async def test_create_requires_auth(client, test_tenant):
    response = await client.post(URL, headers=BASE_HEADERS, json=_payload())
    assert response.status_code in (401, 403)


async def test_create_validates_payload(client, admin_headers):
    response = await client.post(URL, headers=admin_headers, json={"image_url": "x"})
    assert response.status_code == 422


# ------------------------------------------------- isolation entre tenants


async def test_promotions_are_isolated_between_tenants(
    client, admin_headers, other_admin_headers
):
    await _create(client, admin_headers, title="Promo A")
    await _create(client, other_admin_headers, title="Promo B")

    assert await _titles(client, BASE_HEADERS) == ["Promo A"]
    assert await _titles(client, OTHER_HEADERS) == ["Promo B"]


async def test_cannot_update_or_delete_another_tenants_promotion(
    client, admin_headers, other_admin_headers
):
    foreign = await _create(client, other_admin_headers, title="Promo B")
    url = f"{URL}{foreign['id']}"

    patched = await client.patch(url, headers=admin_headers, json={"title": "Piraté"})
    deleted = await client.delete(url, headers=admin_headers)
    assert patched.status_code == 404
    assert deleted.status_code == 404

    # La promotion de l'autre tenant est intacte.
    assert await _titles(client, OTHER_HEADERS) == ["Promo B"]


# ----------------------------------------------- mise à jour / suppression


async def test_update_promotion_changes_only_given_fields(client, admin_headers):
    created = await _create(client, admin_headers, title="Avant", priority=1)

    response = await client.patch(
        f"{URL}{created['id']}",
        headers=admin_headers,
        json={"title": "Après", "priority": 9},
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["title"] == "Après"
    assert data["priority"] == 9
    assert data["image_url"] == created["image_url"]


async def test_delete_is_soft_and_hides_promotion(client, admin_headers, db_session):
    created = await _create(client, admin_headers, title="À retirer")

    response = await client.delete(f"{URL}{created['id']}", headers=admin_headers)
    assert response.status_code == 204

    assert await _titles(client, BASE_HEADERS) == []
    still_there = await db_session.scalar(
        select(Promotion.is_active).where(Promotion.id == uuid.UUID(created["id"]))
    )
    assert still_there is False  # suppression logique : la ligne existe toujours


async def test_update_and_delete_unknown_promotion_return_404(client, admin_headers):
    url = f"{URL}{uuid.uuid4()}"
    assert (await client.patch(url, headers=admin_headers, json={"title": "x"})).status_code == 404
    assert (await client.delete(url, headers=admin_headers)).status_code == 404


# -------------------------------------------- défauts suspectés (xfail)


@pytest.mark.xfail(
    reason=(
        "promotion_id est typé str : un id non-UUID provoque probablement une "
        "erreur DB (500) au lieu d'une 422."
    ),
    strict=False,
)
async def test_update_with_invalid_id_returns_422(client, admin_headers):
    response = await client.patch(
        f"{URL}not-a-uuid", headers=admin_headers, json={"title": "x"}
    )
    assert response.status_code == 422


@pytest.mark.xfail(
    reason=(
        "Les colonnes starts_at/ends_at sont des DateTime naïfs : une date ISO "
        "avec fuseau (« Z ») provoque probablement une erreur asyncpg (500)."
    ),
    strict=False,
)
async def test_create_accepts_timezone_aware_dates(client, admin_headers):
    response = await client.post(
        URL,
        headers=admin_headers,
        json=_payload(starts_at="2026-01-01T00:00:00Z"),
    )
    assert response.status_code == 201


# ------------------------------------------ gestion réservée aux admins


async def test_regular_user_cannot_manage_promotions(
    client, auth_headers, admin_headers
):
    created = await _create(client, admin_headers, title="Officielle")
    url = f"{URL}{created['id']}"

    create = await client.post(URL, headers=auth_headers, json=_payload(title="Pirate"))
    patch = await client.patch(url, headers=auth_headers, json={"title": "Piraté"})
    delete = await client.delete(url, headers=auth_headers)
    assert create.status_code == 403
    assert patch.status_code == 403
    assert delete.status_code == 403

    # Rien n'a changé pour les visiteurs.
    assert await _titles(client, BASE_HEADERS) == ["Officielle"]
