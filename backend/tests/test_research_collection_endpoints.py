"""Tests HTTP des endpoints POST .../research/collection/run et
GET .../research/collection/jobs/{job_id} — isolation tenant, verrou de
concurrence, rate-limit, sur le modèle de test_research_documents.py /
test_research_document_upload.py.

`run_collection_job` est monkeypatché en simulacre : ces tests valident le
contrat HTTP (statuts, 404/409/429, isolation), pas la collecte elle-même
(déjà couverte par test_research_collection.py). Sans ça, BackgroundTasks
exécuterait un vrai job réseau vers Wikimedia à chaque requête de test — et
le job resterait indéfiniment "pending", ce qui fausserait aussi le test du
rate-limit en laissant le verrou de concurrence se déclencher à sa place.
"""
import uuid
from datetime import datetime, timezone

import pytest

from app.models import ResearchCollectionJob


def _run_url(tenant_id):
    return f"/api/v1/tenants/{tenant_id}/research/collection/run"


def _job_url(tenant_id, job_id):
    return f"/api/v1/tenants/{tenant_id}/research/collection/jobs/{job_id}"


@pytest.fixture(autouse=True)
def _noop_collection_runner(monkeypatch):
    """Simule une collecte instantanée : marque le job "done" sans toucher
    au réseau, pour que le verrou de concurrence (pending/processing) ne
    reste pas bloqué indéfiniment et n'interfère pas avec le test du
    rate-limit, qui doit isoler ce seul garde-fou."""

    async def _fake_done(job_id):
        from app.database import AsyncSessionLocal

        async with AsyncSessionLocal() as session:
            job = await session.get(ResearchCollectionJob, job_id)
            if job:
                job.status = "done"
                job.finished_at = datetime.now(timezone.utc).replace(tzinfo=None)
                await session.commit()

    monkeypatch.setattr("app.api.v1.endpoints.tenants.run_collection_job", _fake_done)


@pytest.mark.asyncio
async def test_start_collection_success_202(client, admin_headers, test_tenant):
    response = await client.post(
        _run_url(test_tenant.id),
        headers=admin_headers,
        json={"territory": "Tlemcen", "languages": ["fr"]},
    )
    assert response.status_code == 202
    data = response.json()
    assert data["tenant_id"] == str(test_tenant.id)
    assert data["status"] == "pending"
    assert data["documents_fetched"] == 0


@pytest.mark.asyncio
async def test_start_collection_unknown_tenant_404(client, admin_headers):
    response = await client.post(
        _run_url("00000000-0000-0000-0000-000000000000"),
        headers=admin_headers,
        json={},
    )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_start_collection_is_tenant_isolated(client, other_admin_headers, test_tenant):
    # Isolation des routes /{tenant_id}/... : un admin d'un autre tenant reçoit 404.
    response = await client.post(
        _run_url(test_tenant.id),
        headers=other_admin_headers,
        json={},
    )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_start_collection_rejects_when_job_already_active(
    client, admin_headers, db_session, test_tenant
):
    active = ResearchCollectionJob(tenant_id=test_tenant.id, status="processing")
    db_session.add(active)
    await db_session.commit()

    response = await client.post(_run_url(test_tenant.id), headers=admin_headers, json={})
    assert response.status_code == 409


@pytest.mark.asyncio
async def test_start_collection_rate_limited_after_recent_job(
    client, admin_headers, test_tenant
):
    first = await client.post(_run_url(test_tenant.id), headers=admin_headers, json={})
    assert first.status_code == 202

    second = await client.post(_run_url(test_tenant.id), headers=admin_headers, json={})
    assert second.status_code == 429


@pytest.mark.asyncio
async def test_get_collection_job_status_200(client, admin_headers, db_session, test_tenant):
    job = ResearchCollectionJob(
        tenant_id=test_tenant.id,
        status="done",
        documents_fetched=2,
        documents_new=1,
        documents_duplicate=1,
    )
    db_session.add(job)
    await db_session.commit()
    await db_session.refresh(job)

    response = await client.get(_job_url(test_tenant.id, job.id), headers=admin_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "done"
    assert data["documents_fetched"] == 2


@pytest.mark.asyncio
async def test_get_collection_job_not_found_404(client, admin_headers, test_tenant):
    response = await client.get(
        _job_url(test_tenant.id, uuid.uuid4()), headers=admin_headers
    )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_get_collection_job_is_tenant_isolated(
    client, other_admin_headers, db_session, test_tenant
):
    job = ResearchCollectionJob(tenant_id=test_tenant.id, status="pending")
    db_session.add(job)
    await db_session.commit()
    await db_session.refresh(job)

    response = await client.get(_job_url(test_tenant.id, job.id), headers=other_admin_headers)
    assert response.status_code == 404
