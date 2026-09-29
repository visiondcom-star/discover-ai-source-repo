"""Tests du runner de collecte (run_collection_job) : Wikimedia est simulé par
httpx.MockTransport, la base est la vraie base de test (fixtures conftest)."""
import httpx
from sqlalchemy import select

from app.models import (
    DestinationResearchDocument,
    ResearchCollectionJob,
    ResearchSourceConfig,
)
from app.services.research_collection_service import run_collection_job_with_session
from app.services.wikimedia_client import WIKIMEDIA_LICENSE, WikimediaClient

FILLER = "Contenu détaillé sur la destination, ses paysages et son patrimoine. " * 5


def _wiki_handler(available):
    """`available` : ensemble de (host, titre) qui existent ; les autres sont 'missing'.
    Le texte dépend de l'hôte et du titre pour que chaque page ait un hash distinct.

    Répond aussi aux requêtes de repli (`action=opensearch`) par une liste vide :
    ces tests ne visent pas à exercer le repli (voir
    test_collection_falls_back_to_search_when_exact_title_missing pour ça)."""

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.params.get("action") == "opensearch":
            search = request.url.params.get("search", "")
            return httpx.Response(200, json=[search, [], [], []])
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


async def test_collection_falls_back_to_search_when_exact_title_missing(db_session, test_tenant):
    """Ex. Alger : le nom saisi par l'admin ne correspond pas toujours au
    titre exact de la page (accent, forme longue, homonymie). Le repli par
    `action=opensearch` retrouve la bonne page ; ne s'applique qu'aux cibles
    dérivées du territoire, jamais aux sources 'wiki' ajoutées à la main."""
    tid = test_tenant.id

    def handler(request: httpx.Request) -> httpx.Response:
        host, title = request.url.host, request.url.params.get("titles")
        if request.url.params.get("action") == "opensearch":
            search = request.url.params["search"]
            if host == "fr.wikipedia.org" and search == "Alger ville":
                return httpx.Response(200, json=[search, ["Alger"], [""], [""]])
            return httpx.Response(200, json=[search, [], [], []])
        if host == "fr.wikipedia.org" and title == "Alger":
            return httpx.Response(200, json={"query": {"pages": [{
                "title": "Alger",
                "extract": f"Alger, capitale de l'Algérie. {FILLER}",
                "fullurl": "https://fr.wikipedia.org/wiki/Alger",
            }]}})
        return httpx.Response(200, json={"query": {"pages": [{"title": title, "missing": True}]}})

    job_id = await _new_job(db_session, tid, {"territory": "Alger ville", "languages": ["fr"]})
    await run_collection_job_with_session(db_session, job_id, client=_client(handler))

    job = await db_session.get(ResearchCollectionJob, job_id)
    await db_session.refresh(job)
    assert job.status == "done"
    assert job.documents_new == 1  # seul fr.wikipedia (via repli) a produit une page ; wikivoyage : absent
    docs = await _docs(db_session, tid)
    assert docs[0].source_url == "https://fr.wikipedia.org/wiki/Alger"


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
