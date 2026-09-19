"""Research document ingestion tests."""
import pytest


@pytest.mark.asyncio
async def test_ingest_document_requires_admin(client, auth_headers, test_tenant):
    response = await client.post(
        f"/api/v1/tenants/{test_tenant.id}/research/documents",
        headers=auth_headers,
        json={
            "source_type": "guide",
            "raw_text": "Un texte suffisamment long pour passer la validation min_length.",
        },
    )
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_ingest_document_success(client, admin_headers, test_tenant):
    response = await client.post(
        f"/api/v1/tenants/{test_tenant.id}/research/documents",
        headers=admin_headers,
        json={
            "source_type": "guide",
            "source_url": "https://example.com/guide-algerie",
            "raw_text": "La Casbah d'Alger est un site historique classé par l'UNESCO.",
            "language": "fr",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["tenant_id"] == str(test_tenant.id)
    assert data["source_type"] == "guide"
    assert data["status"] == "raw"
    assert len(data["content_hash"]) == 64  # sha256 hex


@pytest.mark.asyncio
async def test_ingest_document_is_idempotent_on_same_content(
    client, admin_headers, test_tenant
):
    payload = {
        "source_type": "wiki",
        "raw_text": "Le Tassili n'Ajjer est un plateau désertique classé au patrimoine mondial.",
    }
    first = await client.post(
        f"/api/v1/tenants/{test_tenant.id}/research/documents",
        headers=admin_headers,
        json=payload,
    )
    second = await client.post(
        f"/api/v1/tenants/{test_tenant.id}/research/documents",
        headers=admin_headers,
        json=payload,
    )
    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["id"] == second.json()["id"], (
        "redéposer le même texte doit renvoyer le document existant, "
        "pas en créer un doublon"
    )


@pytest.mark.asyncio
async def test_ingest_document_unknown_tenant_404(client, admin_headers):
    response = await client.post(
        "/api/v1/tenants/00000000-0000-0000-0000-000000000000/research/documents",
        headers=admin_headers,
        json={
            "source_type": "autre",
            "raw_text": "Un texte suffisamment long pour passer la validation min_length.",
        },
    )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_ingest_document_rejects_short_text(client, admin_headers, test_tenant):
    response = await client.post(
        f"/api/v1/tenants/{test_tenant.id}/research/documents",
        headers=admin_headers,
        json={"source_type": "guide", "raw_text": "trop court"},
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_ingest_document_rejects_unknown_source_type(
    client, admin_headers, test_tenant
):
    response = await client.post(
        f"/api/v1/tenants/{test_tenant.id}/research/documents",
        headers=admin_headers,
        json={
            "source_type": "reseau_social",
            "raw_text": "Un texte suffisamment long pour passer la validation min_length.",
        },
    )
    assert response.status_code == 422
