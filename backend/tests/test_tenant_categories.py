"""Tests de l'endpoint de validation humaine des catégories.

`PATCH /api/v1/tenants/categories/{category_id}` — publier (`proposed → active`),
rejeter (`proposed → rejected`), retirer (`active → rejected`).

Sans cet endpoint, le pipeline écrit `proposed` mais rien ne peut promuer la
catégorie à `active` : elle resterait invisible pour le trip planner, les
filtres POI et le chat, alors que le modèle porte déjà la colonne `status` et
que le schéma `TenantCategoryStatusUpdate` était écrit en amont.
"""
import uuid

import pytest

from app.models import TenantCategory


async def _make_category(db_session, tenant, status="proposed", slug="sa_oasis"):
    """Insère directement une catégorie (le POST ne sait pas fixer `status`)."""
    category = TenantCategory(
        tenant_id=tenant.id,
        slug=slug,
        label="Oasis du Sahara",
        parent_family="nature",
        status=status,
    )
    db_session.add(category)
    await db_session.commit()
    await db_session.refresh(category)
    return category


def _list_url():
    return "/api/v1/tenants/categories"


def _list_all_url():
    return "/api/v1/tenants/categories/all"


@pytest.mark.asyncio
async def test_admin_list_shows_all_statuses(
    client, admin_headers, db_session, test_tenant
):
    """La file de validation voit `proposed` et `rejected`, pas seulement
    `active` : sans ça, l'admin ne saurait ni quoi valider ni quoi retirer
    définitivement. C'est le pendant de `test_list_categories_returns_only_active`."""
    await _make_category(db_session, test_tenant, status="proposed", slug="ca_prop")
    await _make_category(db_session, test_tenant, status="rejected", slug="ca_rej")
    await _make_category(db_session, test_tenant, status="active", slug="ca_act")

    response = await client.get(_list_all_url(), headers=admin_headers)

    assert response.status_code == 200
    by_slug = {c["slug"]: c["status"] for c in response.json()}
    assert by_slug == {
        "ca_prop": "proposed",
        "ca_rej": "rejected",
        "ca_act": "active",
    }


@pytest.mark.asyncio
async def test_admin_list_requires_admin(
    client, auth_headers, db_session, test_tenant
):
    """Un utilisateur non-admin ne doit pas voir la file de validation."""
    await _make_category(db_session, test_tenant, status="proposed")

    response = await client.get(_list_all_url(), headers=auth_headers)

    assert response.status_code == 403


@pytest.mark.asyncio
async def test_admin_list_is_tenant_isolated(
    client, admin_headers, db_session, other_tenant
):
    """Un admin ne voit que les catégories de son propre tenant."""
    await _make_category(
        db_session, other_tenant, status="proposed", slug="ca_other"
    )

    response = await client.get(_list_all_url(), headers=admin_headers)

    assert response.status_code == 200
    assert response.json() == []


@pytest.mark.asyncio
async def test_list_categories_returns_only_active(
    client, admin_headers, db_session, test_tenant
):
    """`proposed` et `rejected` sont invisibles pour le trip planner, les
    filtres POI et le chat : ces clients consomment ce endpoint, pas un flux
    séparé. Une proposition jamais validée ne doit donc jamais y transiter,
    même sous une forme « en attente » (Principe 5).
    """
    await _make_category(db_session, test_tenant, status="proposed", slug="ca_prop")
    await _make_category(db_session, test_tenant, status="rejected", slug="ca_rej")
    await _make_category(db_session, test_tenant, status="active", slug="ca_act")

    response = await client.get(_list_url(), headers=admin_headers)

    assert response.status_code == 200
    assert [c["slug"] for c in response.json()] == ["ca_act"]


@pytest.mark.asyncio
async def test_publish_makes_category_visible_in_the_list(
    client, admin_headers, db_session, test_tenant
):
    """Chaîne complète : `proposed` invisible, PATCH `active`, puis GET la
    renvoie. C'est la preuve de bout en bout que la validation humaine
    fonctionne."""
    category = await _make_category(db_session, test_tenant, status="proposed")

    before = await client.get(_list_url(), headers=admin_headers)
    assert before.json() == []

    patched = await client.patch(
        _url(category.id), headers=admin_headers, json={"status": "active"}
    )
    assert patched.status_code == 200

    after = await client.get(_list_url(), headers=admin_headers)
    assert [c["slug"] for c in after.json()] == [category.slug]


@pytest.mark.asyncio
async def test_reject_hides_category_forever(
    client, admin_headers, db_session, test_tenant
):
    """`rejected` est invisible dans GET et irrécupérable via PATCH : pas de
    « resurrect » qui ferait réapparaître une catégorie écartée."""
    category = await _make_category(db_session, test_tenant, status="proposed")

    rejected = await client.patch(
        _url(category.id), headers=admin_headers, json={"status": "rejected"}
    )
    assert rejected.status_code == 200

    listed = await client.get(_list_url(), headers=admin_headers)
    assert listed.json() == []

    resurrect = await client.patch(
        _url(category.id), headers=admin_headers, json={"status": "active"}
    )
    assert resurrect.status_code == 400


def _url(category_id):
    return f"/api/v1/tenants/categories/{category_id}"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "start, target",
    [
        ("proposed", "active"),
        ("proposed", "rejected"),
        ("active", "rejected"),
    ],
)
async def test_allowed_transitions_succeed(
    client, admin_headers, db_session, test_tenant, start, target
):
    category = await _make_category(db_session, test_tenant, status=start)

    response = await client.patch(
        _url(category.id), headers=admin_headers, json={"status": target}
    )

    assert response.status_code == 200, response.text
    assert response.json()["status"] == target
    # L'état persiste bien, pas seulement dans la réponse.
    await db_session.refresh(category)
    assert category.status == target


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "start, target",
    [
        ("active", "active"),  # auto-transition
        ("proposed", "proposed"),
        ("rejected", "rejected"),
        ("rejected", "active"),  # resurrect
        ("rejected", "proposed"),  # resurrect
        ("active", "proposed"),  # retour arrière
    ],
)
async def test_forbidden_transitions_return_400(
    client, admin_headers, db_session, test_tenant, start, target
):
    """Pas d'auto-transition ni de « resurrect » : `rejected` est terminal."""
    category = await _make_category(db_session, test_tenant, status=start)

    response = await client.patch(
        _url(category.id), headers=admin_headers, json={"status": target}
    )

    assert response.status_code == 400, response.text
    await db_session.refresh(category)
    assert category.status == start, "le refus ne doit pas modifier la ligne"


@pytest.mark.asyncio
async def test_unknown_category_returns_404(client, admin_headers):
    response = await client.patch(
        _url(uuid.uuid4()), headers=admin_headers, json={"status": "active"}
    )

    assert response.status_code == 404


@pytest.mark.asyncio
async def test_category_of_another_tenant_returns_404(
    client, admin_headers, db_session, other_tenant
):
    """Isolation : le slug envoyé est valide, mais la catégorie lui échappe.

    404 et non 403 : un 403 confirmerait que la catégorie existe ailleurs.
    """
    category = await _make_category(
        db_session, other_tenant, status="proposed", slug="ca_cathedral"
    )

    response = await client.patch(
        _url(category.id), headers=admin_headers, json={"status": "active"}
    )

    assert response.status_code == 404
    await db_session.refresh(category)
    assert category.status == "proposed"


@pytest.mark.asyncio
async def test_invalid_status_value_returns_422(
    client, admin_headers, db_session, test_tenant
):
    """Le pattern du schéma rejette un statut hors de la terminologie."""
    category = await _make_category(db_session, test_tenant)

    response = await client.patch(
        _url(category.id), headers=admin_headers, json={"status": "archived"}
    )

    assert response.status_code == 422
    await db_session.refresh(category)
    assert category.status == "proposed"


@pytest.mark.asyncio
async def test_non_admin_is_refused(
    client, auth_headers, db_session, test_tenant
):
    """Un utilisateur non-admin ne doit pas valider une catégorie."""
    category = await _make_category(db_session, test_tenant)

    response = await client.patch(
        _url(category.id), headers=auth_headers, json={"status": "active"}
    )

    assert response.status_code == 403
    await db_session.refresh(category)
    assert category.status == "proposed"