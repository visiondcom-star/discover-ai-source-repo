"""Tests complémentaires pour app/api/v1/endpoints/tenants.py.

Couvre :
- résolution du tenant par en-tête X-Tenant-Slug (non-régression du bug
  « slug lu en query param ») ;
- isolation entre tenants : catégories, documents de recherche, jobs ;
- contrôle d'accès admin sur les routes d'écriture ;
- idempotence de l'ingestion de documents ;
- rate-limit du manual_refresh (par tenant).

Hypothèses à vérifier contre app/schemas.py (adapter si besoin) :
- CATEGORY_PAYLOAD  -> champs requis de TenantCategoryCreate
- DOCUMENT_PAYLOAD  -> champs requis de ResearchDocumentIngest
- TenantResponse expose bien `id`, TenantUpdate accepte `name`
"""
import uuid

import pytest

pytestmark = pytest.mark.asyncio

API = "/api/v1/tenants"
BASE_SLUG = "test-tenant"
OTHER_SLUG = "other-tenant"

CATEGORY_PAYLOAD = {
    "slug": "local-crafts",
    "label": "Artisanat local",
    "parent_family": "culture",
}

DOCUMENT_PAYLOAD = {
    "source_type": "guide",
    "source_url": "https://example.org/guide",
    "raw_text": "Un massif montagneux propose de nombreux sentiers de randonnée.",
    "language": "fr",
}

RUN_MANUAL = {"trigger_type": "manual_refresh"}


# ---------------------------------------------------------------- helpers


async def _tenant_id(client, slug):
    response = await client.get(f"{API}/current", headers={"X-Tenant-Slug": slug})
    assert response.status_code == 200, response.text
    return response.json()["id"]


# ------------------------------------------- résolution du tenant (header)


async def test_current_tenant_unknown_slug_returns_404(client, test_tenant):
    response = await client.get(
        f"{API}/current", headers={"X-Tenant-Slug": "does-not-exist"}
    )
    assert response.status_code == 404


async def test_current_tenant_follows_header_not_query_param(
    client, test_tenant, other_tenant
):
    # Non-régression : le slug doit venir de l'en-tête, jamais du query param.
    response = await client.get(
        f"{API}/current",
        params={"slug": OTHER_SLUG},
        headers={"X-Tenant-Slug": BASE_SLUG},
    )
    assert response.status_code == 200
    assert response.json()["slug"] == BASE_SLUG

    response = await client.get(
        f"{API}/current", headers={"X-Tenant-Slug": OTHER_SLUG}
    )
    assert response.status_code == 200
    assert response.json()["slug"] == OTHER_SLUG


# --------------------------------------------------------------- catégories


async def test_create_category_requires_admin(client, test_tenant, auth_headers):
    headers = {**auth_headers, "X-Tenant-Slug": BASE_SLUG}
    response = await client.post(
        f"{API}/categories", headers=headers, json=CATEGORY_PAYLOAD
    )
    assert response.status_code == 403

    response = await client.post(
        f"{API}/categories",
        headers={"X-Tenant-Slug": BASE_SLUG},
        json=CATEGORY_PAYLOAD,
    )
    assert response.status_code in (401, 403)


async def test_admin_cannot_create_category_in_another_tenant(
    client, admin_headers, test_tenant, other_tenant
):
    # Le jeton admin est lié à un tenant : viser un autre slug est refusé.
    response = await client.post(
        f"{API}/categories",
        headers={**admin_headers, "X-Tenant-Slug": OTHER_SLUG},
        json=CATEGORY_PAYLOAD,
    )
    assert response.status_code == 403
    assert "mismatch" in response.json()["detail"].lower()

    # Rien n'a été créé dans l'autre tenant.
    listed = await client.get(
        f"{API}/categories", headers={"X-Tenant-Slug": OTHER_SLUG}
    )
    assert CATEGORY_PAYLOAD["slug"] not in [c["slug"] for c in listed.json()]


async def test_categories_are_isolated_between_tenants(
    client, admin_headers, test_tenant, other_tenant
):
    created = await client.post(
        f"{API}/categories",
        headers={**admin_headers, "X-Tenant-Slug": BASE_SLUG},
        json=CATEGORY_PAYLOAD,
    )
    assert created.status_code == 201, created.text

    mine = await client.get(f"{API}/categories", headers={"X-Tenant-Slug": BASE_SLUG})
    theirs = await client.get(
        f"{API}/categories", headers={"X-Tenant-Slug": OTHER_SLUG}
    )
    assert mine.status_code == 200 and theirs.status_code == 200
    assert CATEGORY_PAYLOAD["slug"] in [c["slug"] for c in mine.json()]
    assert CATEGORY_PAYLOAD["slug"] not in [c["slug"] for c in theirs.json()]


async def test_category_slug_must_be_unique_within_tenant(
    client, admin_headers, test_tenant
):
    headers = {**admin_headers, "X-Tenant-Slug": BASE_SLUG}

    first = await client.post(
        f"{API}/categories", headers=headers, json=CATEGORY_PAYLOAD
    )
    assert first.status_code == 201, first.text

    duplicate = await client.post(
        f"{API}/categories", headers=headers, json=CATEGORY_PAYLOAD
    )
    assert duplicate.status_code == 400
    assert "already exists" in duplicate.json()["detail"]


# ------------------------------------------------------------ update tenant


async def test_update_tenant_requires_admin(client, test_tenant, auth_headers):
    tenant_id = await _tenant_id(client, BASE_SLUG)
    response = await client.patch(
        f"{API}/{tenant_id}", headers=auth_headers, json={"name": "Hacked"}
    )
    assert response.status_code == 403


async def test_update_tenant_partial_update_keeps_other_fields(
    client, admin_headers, test_tenant
):
    before = (
        await client.get(f"{API}/current", headers={"X-Tenant-Slug": BASE_SLUG})
    ).json()

    response = await client.patch(
        f"{API}/{before['id']}", headers=admin_headers, json={"name": "Renamed"}
    )
    assert response.status_code == 200, response.text
    after = response.json()
    assert after["name"] == "Renamed"
    assert after["slug"] == before["slug"]
    assert after["default_currency"] == before["default_currency"]


async def test_update_tenant_unknown_id_returns_404(client, admin_headers):
    response = await client.patch(
        f"{API}/{uuid.uuid4()}", headers=admin_headers, json={"name": "x"}
    )
    assert response.status_code == 404


async def test_update_tenant_invalid_id_returns_422(client, admin_headers):
    response = await client.patch(
        f"{API}/not-a-uuid", headers=admin_headers, json={"name": "x"}
    )
    assert response.status_code == 422


# ------------------------------------------- ingestion de documents (research)


async def test_ingest_document_requires_admin(client, test_tenant, auth_headers):
    tenant_id = await _tenant_id(client, BASE_SLUG)
    response = await client.post(
        f"{API}/{tenant_id}/research/documents",
        headers=auth_headers,
        json=DOCUMENT_PAYLOAD,
    )
    assert response.status_code == 403


async def test_ingest_document_unknown_tenant_returns_404(client, admin_headers):
    response = await client.post(
        f"{API}/{uuid.uuid4()}/research/documents",
        headers=admin_headers,
        json=DOCUMENT_PAYLOAD,
    )
    assert response.status_code == 404


async def test_ingest_document_is_idempotent(client, admin_headers, test_tenant):
    tenant_id = await _tenant_id(client, BASE_SLUG)
    url = f"{API}/{tenant_id}/research/documents"

    first = await client.post(url, headers=admin_headers, json=DOCUMENT_PAYLOAD)
    assert first.status_code == 200, first.text

    # Le hash est calculé sur le texte strippé : des espaces autour ne créent
    # pas de doublon.
    padded = {**DOCUMENT_PAYLOAD, "raw_text": DOCUMENT_PAYLOAD["raw_text"] + "  \n"}
    second = await client.post(url, headers=admin_headers, json=padded)
    assert second.status_code == 200, second.text
    assert second.json()["id"] == first.json()["id"]


async def test_same_document_in_two_tenants_creates_two_documents(
    client, admin_headers, other_admin_headers
):
    id_a = await _tenant_id(client, BASE_SLUG)
    id_b = await _tenant_id(client, OTHER_SLUG)

    doc_a = await client.post(
        f"{API}/{id_a}/research/documents", headers=admin_headers, json=DOCUMENT_PAYLOAD
    )
    doc_b = await client.post(
        f"{API}/{id_b}/research/documents",
        headers=other_admin_headers,
        json=DOCUMENT_PAYLOAD,
    )
    assert doc_a.status_code == 200 and doc_b.status_code == 200
    # L'idempotence est par (tenant_id, content_hash), jamais globale.
    assert doc_a.json()["id"] != doc_b.json()["id"]


# ------------------------------------------------------ jobs de recherche IA


async def test_run_research_requires_admin(client, test_tenant, auth_headers):
    tenant_id = await _tenant_id(client, BASE_SLUG)
    response = await client.post(
        f"{API}/{tenant_id}/research/run", headers=auth_headers, json=RUN_MANUAL
    )
    assert response.status_code == 403


async def test_run_research_unknown_tenant_returns_404(client, admin_headers):
    response = await client.post(
        f"{API}/{uuid.uuid4()}/research/run", headers=admin_headers, json=RUN_MANUAL
    )
    assert response.status_code == 404


async def test_run_research_returns_202_and_job_completes(
    client, admin_headers, test_tenant
):
    tenant_id = await _tenant_id(client, BASE_SLUG)

    response = await client.post(
        f"{API}/{tenant_id}/research/run", headers=admin_headers, json=RUN_MANUAL
    )
    assert response.status_code == 202, response.text
    job = response.json()
    assert job["status"] == "pending"
    assert job["trigger_type"] == "manual_refresh"

    # Avec ASGITransport, la tâche de fond (stub) est terminée quand la
    # réponse revient. Si ce test reste en "pending", la tâche n'utilise pas
    # la base de test : à investiguer dans conftest.py.
    status = await client.get(
        f"{API}/{tenant_id}/research/jobs/{job['id']}", headers=admin_headers
    )
    assert status.status_code == 200, status.text
    assert status.json()["status"] == "done"


async def test_manual_refresh_is_rate_limited_per_tenant(
    client, admin_headers, other_admin_headers
):
    id_a = await _tenant_id(client, BASE_SLUG)
    id_b = await _tenant_id(client, OTHER_SLUG)

    first = await client.post(
        f"{API}/{id_a}/research/run", headers=admin_headers, json=RUN_MANUAL
    )
    assert first.status_code == 202, first.text

    again = await client.post(
        f"{API}/{id_a}/research/run", headers=admin_headers, json=RUN_MANUAL
    )
    assert again.status_code == 429

    # Le cooldown d'un tenant ne bloque pas un autre tenant.
    other = await client.post(
        f"{API}/{id_b}/research/run", headers=other_admin_headers, json=RUN_MANUAL
    )
    assert other.status_code == 202, other.text


async def test_research_job_is_not_visible_from_another_tenant(
    client, admin_headers, other_admin_headers
):
    id_a = await _tenant_id(client, BASE_SLUG)
    id_b = await _tenant_id(client, OTHER_SLUG)

    job = (
        await client.post(
            f"{API}/{id_a}/research/run", headers=admin_headers, json=RUN_MANUAL
        )
    ).json()

    own = await client.get(
        f"{API}/{id_a}/research/jobs/{job['id']}", headers=admin_headers
    )
    assert own.status_code == 200

    foreign = await client.get(
        f"{API}/{id_b}/research/jobs/{job['id']}", headers=other_admin_headers
    )
    assert foreign.status_code == 404


async def test_research_job_unknown_id_returns_404(
    client, admin_headers, test_tenant
):
    tenant_id = await _tenant_id(client, BASE_SLUG)
    response = await client.get(
        f"{API}/{tenant_id}/research/jobs/{uuid.uuid4()}", headers=admin_headers
    )
    assert response.status_code == 404


async def test_research_job_status_requires_admin(client, test_tenant, auth_headers):
    tenant_id = await _tenant_id(client, BASE_SLUG)
    response = await client.get(
        f"{API}/{tenant_id}/research/jobs/{uuid.uuid4()}", headers=auth_headers
    )
    assert response.status_code == 403


# ------------------------------------------- isolation des admins par tenant


async def test_admin_cannot_ingest_document_into_another_tenant(
    client, admin_headers, test_tenant, other_tenant
):
    id_b = await _tenant_id(client, OTHER_SLUG)
    response = await client.post(
        f"{API}/{id_b}/research/documents",
        headers=admin_headers,
        json=DOCUMENT_PAYLOAD,
    )
    assert response.status_code in (403, 404)


async def test_admin_cannot_update_another_tenant(
    client, admin_headers, test_tenant, other_tenant
):
    id_b = await _tenant_id(client, OTHER_SLUG)
    response = await client.patch(
        f"{API}/{id_b}", headers=admin_headers, json={"name": "Hijacked"}
    )
    assert response.status_code in (403, 404)


async def test_admin_cannot_start_research_for_another_tenant(
    client, admin_headers, test_tenant, other_tenant
):
    id_b = await _tenant_id(client, OTHER_SLUG)
    response = await client.post(
        f"{API}/{id_b}/research/run", headers=admin_headers, json=RUN_MANUAL
    )
    assert response.status_code in (403, 404)


async def test_list_tenants_returns_only_the_admin_tenant(
    client, admin_headers, other_admin_headers
):
    mine = await client.get(f"{API}/", headers=admin_headers)
    theirs = await client.get(f"{API}/", headers=other_admin_headers)
    assert mine.status_code == 200 and theirs.status_code == 200
    assert [t["slug"] for t in mine.json()] == [BASE_SLUG]
    assert [t["slug"] for t in theirs.json()] == [OTHER_SLUG]


async def test_same_category_slug_is_allowed_in_another_tenant(
    client, admin_headers, other_admin_headers
):
    for headers in (admin_headers, other_admin_headers):
        response = await client.post(
            f"{API}/categories", headers=headers, json=CATEGORY_PAYLOAD
        )
        assert response.status_code == 201, response.text


async def test_admin_cannot_read_research_job_of_another_tenant_by_url(
    client, admin_headers, other_admin_headers
):
    id_a = await _tenant_id(client, BASE_SLUG)
    job = (
        await client.post(
            f"{API}/{id_a}/research/run", headers=admin_headers, json=RUN_MANUAL
        )
    ).json()

    response = await client.get(
        f"{API}/{id_a}/research/jobs/{job['id']}", headers=other_admin_headers
    )
    assert response.status_code == 404
