"""Tests du runner de collecte (run_collection_job) : Wikimedia est simulé par
httpx.MockTransport, la base est la vraie base de test (fixtures conftest)."""
import httpx
from sqlalchemy import func, select

import app.services.research_service as research_service_module
from app.models import (
    DestinationResearchDocument,
    ResearchCollectionJob,
    ResearchJob,
    ResearchSourceConfig,
)
from app.services import research_collection_service as collection_service
from app.services.llm_providers.base import CompletionResult, TokenUsage
from app.services.research_collection_service import run_collection_job
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
    await run_collection_job(db_session, job_id, client=_client(handler))

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
    await run_collection_job(db_session, job2_id, client=_client(handler))
    job2 = await db_session.get(ResearchCollectionJob, job2_id)
    await db_session.refresh(job2)
    assert job2.status == "done"
    assert (job2.documents_new, job2.documents_duplicate) == (0, 1)
    assert len(await _docs(db_session, tid)) == 1


async def test_collection_fails_when_wikimedia_unreachable(db_session, test_tenant):
    tid = test_tenant.id
    job_id = await _new_job(db_session, tid, {"territory": "Kabylie", "languages": ["fr"]})

    await run_collection_job(db_session, job_id, client=_client(lambda r: httpx.Response(503)))

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
    await run_collection_job(db_session, job_id, client=_client(handler))

    job = await db_session.get(ResearchCollectionJob, job_id)
    await db_session.refresh(job)
    assert job.status == "done"
    assert job.documents_new == 1

    docs = await _docs(db_session, tid)
    assert [d.source_url for d in docs] == ["https://fr.wikivoyage.org/wiki/Tizi_Ouzou"]


async def test_collection_endpoint_rate_limited_by_recent_run(
    client, admin_headers, test_tenant, db_session
):
    await _new_job(db_session, test_tenant.id, {"territory": "Kabylie"})

    response = await client.post(
        f"{API}/{test_tenant.id}/research/collection/run", headers=admin_headers, json={}
    )

    assert response.status_code == 429
    assert await _count(db_session, ResearchCollectionJob, test_tenant.id) == 1


async def test_collection_endpoint_allows_retry_after_failed_run(
    client, admin_headers, test_tenant, db_session, monkeypatch
):
    job_id = await _new_job(db_session, test_tenant.id, {})
    job = await db_session.get(ResearchCollectionJob, job_id)
    job.status = "failed"  # un échec ne consomme pas la fenêtre (erreur réseau)
    await db_session.commit()

    _patch_wiki(monkeypatch, set())
    response = await client.post(
        f"{API}/{test_tenant.id}/research/collection/run",
        headers=admin_headers,
        json={"territory": "Kabylie"},
    )

    assert response.status_code == 202
    assert await _count(db_session, ResearchCollectionJob, test_tenant.id) == 2


async def test_collection_endpoint_rejects_invalid_languages(
    client, admin_headers, test_tenant, db_session
):
    response = await client.post(
        f"{API}/{test_tenant.id}/research/collection/run",
        headers=admin_headers,
        json={"languages": ["FR"]},  # un code invalide ferait échouer tout le job en plein run
    )

    assert response.status_code == 422
    assert await _count(db_session, ResearchCollectionJob, test_tenant.id) == 0


async def test_collection_endpoint_skips_pipeline_when_nothing_new(
    client, admin_headers, test_tenant, db_session, monkeypatch
):
    _patch_wiki(monkeypatch, set())  # aucun titre disponible sur aucun projet
    _patch_llm(monkeypatch)

    job = await _start_and_poll(
        client, admin_headers, test_tenant.id, {"territory": "Kabylie", "languages": ["fr"]}
    )

    assert job["status"] == "failed"  # rien collecté : échec, pas un "done" vide
    assert job["documents_new"] == 0 and job["documents_failed"] == 2
    assert await _docs(db_session, test_tenant.id) == []
    # Aucun run LLM : il n'y a rien de nouveau à extraire.
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


def _patch_llm(monkeypatch, reply="[]"):
    """Provider LLM factice : le chaînage ne doit pas dépendre d'un vrai credential."""

    class FakeProvider:
        name = "openai"
        configured_model = "gpt-4o"

        async def complete(self, messages, temperature=0.3, max_tokens=2000):
            return CompletionResult(
                text=reply,
                model="gpt-4o",
                usage=TokenUsage(prompt_tokens=1, completion_tokens=1),
            )

    async def fake_resolver(db, tenant_id, feature):
        return FakeProvider()

    monkeypatch.setattr(research_service_module, "get_tenant_llm_provider", fake_resolver)


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


async def test_collection_endpoint_runs_and_chains_pipeline(
    client, admin_headers, test_tenant, db_session, monkeypatch
):
    _patch_wiki(monkeypatch, {("fr.wikivoyage.org", "Kabylie")})
    _patch_llm(monkeypatch)

    job = await _start_and_poll(
        client, admin_headers, test_tenant.id, {"territory": "Kabylie", "languages": ["fr"]}
    )

    assert job["status"] == "done"
    assert job["error_message"]
    assert (
        job["documents_fetched"],
        job["documents_new"],
        job["documents_duplicate"],
        job["documents_failed"],
    ) == (1, 1, 0, 1)
    assert job["params"] == {"territory": "Kabylie", "languages": ["fr"]}
    assert job["started_at"] and job["finished_at"]

    docs = await _docs(db_session, test_tenant.id)
    assert len(docs) == 1
    assert (docs[0].source_type, docs[0].status, docs[0].license) == (
        "wiki",
        "raw",
        WIKIMEDIA_LICENSE,
    )

    # Chaînage : un ResearchJob "scheduled" a été créé ET exécuté. "scheduled" et
    # non "manual_refresh" : un run automatique ne doit pas consommer le cooldown
    # de l'admin.
    runs = (
        await db_session.execute(
            select(ResearchJob).where(ResearchJob.tenant_id == test_tenant.id)
        )
    ).scalars().all()
    assert len(runs) == 1
    assert runs[0].trigger_type == "scheduled"
    assert runs[0].status == "done"

