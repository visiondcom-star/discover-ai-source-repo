"""Tests du runner de collecte (run_collection_job) : Wikimedia est simulé par
httpx.MockTransport, la base est la vraie base de test (fixtures conftest)."""
import httpx
from sqlalchemy import func, select

from app.constants import RESEARCH_COLLECTION_COOLDOWN_MINUTES
from app.models import (
    DestinationResearchDocument,
    ResearchCollectionJob,
    ResearchJob,
    ResearchSourceConfig,
)
from app.services import research_collection_service as collection_service
from app.services.research_collection_service import run_collection_job_with_session
from app.services.wikimedia_client import WIKIMEDIA_LICENSE, WikimediaClient

FILLER = "Contenu détaillé sur la destination, ses paysages et son patrimoine. " * 5


def _wiki_handler(available):
    """`available` : ensemble de (host, titre) qui existent ; les autres sont 'missing'.
    Le texte dépend de l'hôte et du titre pour que chaque page ait un hash distinct."""

    def handler(request: httpx.Request) -> httpx.Response:
        host = request.url.host
        title = request.url.params["titles"]
        if (host, title) not in available:
            return httpx.Response(200, json={"query": {"pages": [{"title": title, "missing": True}]}})
        page_url = f"https://{host}/wiki/{title.replace(' ', '_')}"
        return httpx.Response(200, json={"query": {"pages": [{
            "title": title,
            "extract": f"{host} — {title}. {FILLER}",
            "fullurl": page_url,
        }]}})

    return handler


def _client(handler):
    return WikimediaClient(transport=httpx.MockTransport(handler))


async def _new_job(db, tenant_id, params):
    job = ResearchCollectionJob(tenant_id=tenant_id, params=params)
    db.add(job)
    await db.commit()
    await db.refresh(job)
    return job.id


async def _docs(db, tenant_id):
    res = await db.execute(
        select(DestinationResearchDocument).where(DestinationResearchDocument.tenant_id == tenant_id)
    )
    return res.scalars().all()


async def test_collection_creates_documents_then_counts_duplicates(db_session, test_tenant):
    tid = test_tenant.id
    handler = _wiki_handler({("fr.wikivoyage.org", "Kabylie")})
    params = {"territory": "Kabylie", "languages": ["fr"]}

    job_id = await _new_job(db_session, tid, params)
    await run_collection_job_with_session(db_session, job_id, client=_client(handler))

    job = await db_session.get(ResearchCollectionJob, job_id)
    await db_session.refresh(job)
    assert job.status == "done"
    assert job.started_at is not None and job.finished_at is not None
    assert (job.documents_fetched, job.documents_new, job.documents_duplicate) == (1, 1, 0)
    assert job.documents_failed == 1  # fr.wikipedia.org/Kabylie absent dans le scénario

    docs = await _docs(db_session, tid)
    assert len(docs) == 1
    doc = docs[0]
    assert doc.source_type == "wiki"
    assert doc.language == "fr"
    assert doc.status == "raw"
    assert doc.license == WIKIMEDIA_LICENSE
    assert "Wikivoyage" in doc.attribution
    assert doc.source_url == "https://fr.wikivoyage.org/wiki/Kabylie"

    # Second passage : idempotent, tout est compté en doublon
    job2_id = await _new_job(db_session, tid, params)
    await run_collection_job_with_session(db_session, job2_id, client=_client(handler))
    job2 = await db_session.get(ResearchCollectionJob, job2_id)
    await db_session.refresh(job2)
    assert job2.status == "done"
    assert (job2.documents_new, job2.documents_duplicate) == (0, 1)
    assert len(await _docs(db_session, tid)) == 1


async def test_collection_fails_when_wikimedia_unreachable(db_session, test_tenant):
    tid = test_tenant.id
    job_id = await _new_job(db_session, tid, {"territory": "Kabylie", "languages": ["fr"]})

    await run_collection_job_with_session(db_session, job_id, client=_client(lambda r: httpx.Response(503)))

    job = await db_session.get(ResearchCollectionJob, job_id)
    await db_session.refresh(job)
    assert job.status == "failed"
    assert job.documents_new == 0 and job.documents_failed == 2
    assert job.error_message
    assert await _docs(db_session, tid) == []


async def test_collection_uses_manual_wiki_sources_and_ignores_others(db_session, test_tenant):
    tid = test_tenant.id
    db_session.add_all([
        ResearchSourceConfig(
            tenant_id=tid, name="Tizi Ouzou (wikivoyage)",
            url="https://fr.wikivoyage.org/wiki/Tizi_Ouzou", source_type="wiki",
        ),
        ResearchSourceConfig(
            tenant_id=tid, name="Office du tourisme",
            url="https://office.example.dz/accueil", source_type="office_tourisme",
        ),
    ])
    await db_session.commit()

    handler = _wiki_handler({("fr.wikivoyage.org", "Tizi Ouzou")})
    # Pas de "territory" : le repli sur tenant.name ("Test Tenant") ne trouve rien
    job_id = await _new_job(db_session, tid, {"languages": ["fr"]})
    await run_collection_job_with_session(db_session, job_id, client=_client(handler))

    job = await db_session.get(ResearchCollectionJob, job_id)
    await db_session.refresh(job)
    assert job.status == "done"
    assert job.documents_new == 1

    docs = await _docs(db_session, tid)
    assert [d.source_url for d in docs] == ["https://fr.wikivoyage.org/wiki/Tizi_Ouzou"]


async def test_collection_endpoint_rejects_concurrent_run_with_409(
    client, admin_headers, test_tenant, db_session
):
    # Un job "pending" existe déjà : garde-fou concurrence (409), avant le 429.
    await _new_job(db_session, test_tenant.id, {"territory": "Kabylie"})

    response = await client.post(
        f"{API}/{test_tenant.id}/research/collection/run", headers=admin_headers, json={}
    )

    assert response.status_code == 409
    assert response.json()["detail"] == "Une collecte est déjà en cours pour ce tenant."
    assert await _count(db_session, ResearchCollectionJob, test_tenant.id) == 1


async def test_collection_endpoint_cooldown_applies_whatever_final_status(
    client, admin_headers, test_tenant, db_session
):
    job_id = await _new_job(db_session, test_tenant.id, {})
    job = await db_session.get(ResearchCollectionJob, job_id)
    job.status = "done"
    await db_session.commit()

    # Job terminal récent -> 429 (fenêtre des RESEARCH_COLLECTION_COOLDOWN_MINUTES min).
    first = await client.post(
        f"{API}/{test_tenant.id}/research/collection/run",
        headers=admin_headers,
        json={"territory": "Kabylie"},
    )
    assert first.status_code == 429
    assert str(RESEARCH_COLLECTION_COOLDOWN_MINUTES) in first.json()["detail"]

    # Même réponse si le job précédent a échoué : le statut final n'importe pas.
    job.status = "failed"
    await db_session.commit()
    second = await client.post(
        f"{API}/{test_tenant.id}/research/collection/run", headers=admin_headers, json={}
    )
    assert second.status_code == 429
    assert await _count(db_session, ResearchCollectionJob, test_tenant.id) == 1


async def test_collection_endpoint_fails_cleanly_on_invalid_language(
    client, admin_headers, test_tenant, db_session, monkeypatch
):
    _patch_wiki(monkeypatch, set())  # aucune requête réseau : la validation échoue avant
    job = await _start_and_poll(
        client, admin_headers, test_tenant.id, {"languages": ["FR"]}
    )

    # Le runner ne rattrape pas ValueError : le job échoue proprement (failed)
    # avec l'erreur remontée, sans que l'endpoint lève une 500.
    assert job["status"] == "failed"
    assert "langue" in (job["error_message"] or "")
    assert job["documents_new"] == 0
    assert await _docs(db_session, test_tenant.id) == []


async def test_collection_endpoint_fails_when_nothing_collected(
    client, admin_headers, test_tenant, db_session, monkeypatch
):
    _patch_wiki(monkeypatch, set())  # aucun titre disponible sur aucun projet

    job = await _start_and_poll(
        client, admin_headers, test_tenant.id, {"territory": "Kabylie", "languages": ["fr"]}
    )

    assert job["status"] == "failed"  # rien collecté : échec, pas un "done" vide
    assert job["documents_new"] == 0 and job["documents_failed"] == 2
    assert await _docs(db_session, test_tenant.id) == []
    # Aucune extraction LLM n'est lancée : la collecte et l'extraction restent
    # deux étapes indépendantes.
    assert await _count(db_session, ResearchJob, test_tenant.id) == 0


async def test_collection_endpoint_is_tenant_isolated(
    client, admin_headers, other_admin_headers, test_tenant, other_tenant, db_session, monkeypatch
):
    _patch_wiki(monkeypatch, set())

    # Admin du tenant A sur le tenant B, et inversement : 404 (ni 403, ni fuite).
    assert (
        await client.post(
            f"{API}/{other_tenant.id}/research/collection/run", headers=admin_headers, json={}
        )
    ).status_code == 404
    assert (
        await client.post(
            f"{API}/{test_tenant.id}/research/collection/run",
            headers=other_admin_headers,
            json={},
        )
    ).status_code == 404

    job = await _start_and_poll(client, admin_headers, test_tenant.id, {})
    assert (
        await client.get(
            f"{API}/{other_tenant.id}/research/collection/jobs/{job['id']}",
            headers=other_admin_headers,
        )
    ).status_code == 404
    assert await _count(db_session, ResearchCollectionJob, other_tenant.id) == 0




# ===== Endpoint POST /{tenant_id}/research/collection/run (tâche de fond) =====

API = "/api/v1/tenants"


def _patch_wiki(monkeypatch, available):
    """Force le client Wikimedia du runner à passer par le transport simulé.

    La tâche de fond instancie elle-même `WikimediaClient()` : on patche le nom
    dans le module du runner pour qu'aucun test ne sorte sur Internet.
    """
    monkeypatch.setattr(
        collection_service,
        "WikimediaClient",
        lambda *args, **kwargs: WikimediaClient(
            transport=httpx.MockTransport(_wiki_handler(available))
        ),
    )


async def _start_and_poll(client, headers, tenant_id, payload):
    """POST puis poll du job : avec ASGITransport, la tâche de fond (collecte +
    chaînage) est terminée quand la réponse du POST revient."""
    response = await client.post(
        f"{API}/{tenant_id}/research/collection/run", headers=headers, json=payload
    )
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    polled = await client.get(
        f"{API}/{tenant_id}/research/collection/jobs/{job_id}", headers=headers
    )
    assert polled.status_code == 200, polled.text
    return polled.json()


async def _count(db, model, tenant_id):
    res = await db.execute(
        select(func.count()).select_from(model).where(model.tenant_id == tenant_id)
    )
    return res.scalar_one()


async def test_collection_endpoint_runs_and_reports_counters(
    client, admin_headers, test_tenant, db_session, monkeypatch
):
    _patch_wiki(monkeypatch, {("fr.wikivoyage.org", "Kabylie")})

    job = await _start_and_poll(
        client, admin_headers, test_tenant.id, {"territory": "Kabylie", "languages": ["fr"]}
    )

    assert job["status"] == "done"
    assert job["error_message"]  # fr.wikipedia/Kabylie absent : remonté dans l'erreur
    assert (
        job["documents_fetched"],
        job["documents_new"],
        job["documents_duplicate"],
        job["documents_failed"],
    ) == (1, 1, 0, 1)
    assert job["started_at"] and job["finished_at"]

    docs = await _docs(db_session, test_tenant.id)
    assert len(docs) == 1
    assert (docs[0].source_type, docs[0].status, docs[0].license) == (
        "wiki",
        "raw",
        WIKIMEDIA_LICENSE,
    )

    # La collecte stocke en "raw" et ne déclenche PAS le pipeline d'extraction
    # (extraction = /research/run, séparée et tarifée à part).
    assert await _count(db_session, ResearchJob, test_tenant.id) == 0

