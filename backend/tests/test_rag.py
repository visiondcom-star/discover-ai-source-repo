"""Tests RAG : isolation entre tenants (principe 3 du CLAUDE.md) et chemins de recherche.

Les embeddings passent par le provider LLM configure (principe 7) : ce module
ne parle jamais directement a une API d'embeddings. Par defaut en test, aucun
vrai provider n'est configure : RAGService recoit un MockProvider (via la
factory), ce qui declenche le garde explicite et refuse d'indexer / de
chercher par similarite -- ce comportement est verifie ci-dessous plutot que
suppose. Le chemin pgvector est teste separement avec un faux provider
deterministe (fake_provider / broken_provider), sans reseau.
"""
import logging

import pytest
from sqlalchemy import select

import app.services.rag_service as rag_service
from app.models import POI
from app.services.llm_providers.mock_provider import MockProvider
from app.services.rag_service import RAGService

SEARCH_URL = "/api/v1/rag/search"
INDEX_URL = "/api/v1/rag/index"


def _poi(tenant, slug, name, city="Alger", description=None, is_active=True):
    return POI(
        tenant_id=tenant.id,
        slug=slug,
        name=name,
        city=city,
        description=description,
        categories=[],
        is_active=is_active,
    )


def _fake_embedding(text):
    """Vecteur unitaire deterministe : 'plage' -> e0, 'ruines' -> e1, sinon e2."""
    vec = [0.0] * 1536
    lowered = text.lower()
    if "plage" in lowered:
        vec[0] = 1.0
    elif "ruines" in lowered:
        vec[1] = 1.0
    else:
        vec[2] = 1.0
    return vec


class _FakeProvider:
    async def embed(self, text):
        return _fake_embedding(text)


class _BrokenProvider:
    async def embed(self, text):
        raise RuntimeError("API down")


@pytest.fixture(autouse=True)
def _default_no_real_provider(monkeypatch):
    """Hermetique par defaut : aucun vrai provider, meme si un .env local en a un."""
    monkeypatch.setattr(rag_service, "get_llm_provider", lambda: MockProvider())


@pytest.fixture
def fake_provider(monkeypatch, _default_no_real_provider):
    monkeypatch.setattr(rag_service, "get_llm_provider", lambda: _FakeProvider())


@pytest.fixture
def broken_provider(monkeypatch, _default_no_real_provider):
    monkeypatch.setattr(rag_service, "get_llm_provider", lambda: _BrokenProvider())


# ------------------------------------------------------------- endpoints


async def test_rag_search_never_returns_other_tenant_pois(
    client, auth_headers, other_admin_headers, test_tenant, other_tenant, db_session
):
    db_session.add_all(
        [
            _poi(test_tenant, "casbah-a", "Casbah d'Alger", description="Vieille medina"),
            _poi(other_tenant, "casbah-b", "Casbah de l'autre tenant", description="Medina"),
        ]
    )
    await db_session.commit()

    mine = await client.post(SEARCH_URL, headers=auth_headers, json={"query": "casbah"})
    theirs = await client.post(
        SEARCH_URL, headers=other_admin_headers, json={"query": "casbah"}
    )
    assert mine.status_code == 200, mine.text
    assert theirs.status_code == 200, theirs.text
    assert [r["name"] for r in mine.json()["results"]] == ["Casbah d'Alger"]
    assert [r["name"] for r in theirs.json()["results"]] == ["Casbah de l'autre tenant"]


async def test_rag_search_requires_auth(client, test_tenant):
    response = await client.post(
        SEARCH_URL, headers={"X-Tenant-Slug": "test-tenant"}, json={"query": "casbah"}
    )
    assert response.status_code in (401, 403)


async def test_rag_search_validates_payload(client, auth_headers):
    empty = await client.post(SEARCH_URL, headers=auth_headers, json={"query": ""})
    assert empty.status_code == 422

    too_many = await client.post(
        SEARCH_URL, headers=auth_headers, json={"query": "x", "top_k": 21}
    )
    assert too_many.status_code == 422


async def test_rag_index_requires_admin(client, auth_headers, test_tenant):
    response = await client.post(INDEX_URL, headers=auth_headers)
    assert response.status_code == 403


async def test_rag_index_endpoint_indexes_only_the_callers_tenant(
    client, admin_headers, test_tenant, other_tenant, db_session, fake_provider
):
    db_session.add_all(
        [
            _poi(test_tenant, "plage-a", "Plage de Tipaza"),
            _poi(other_tenant, "plage-b", "Plage secrete"),
        ]
    )
    await db_session.commit()

    response = await client.post(INDEX_URL, headers=admin_headers)
    assert response.status_code == 200, response.text
    assert response.json() == {"indexed": 1, "tenant": "test-tenant"}

    own = await db_session.scalar(select(POI.embedding).where(POI.slug == "plage-a"))
    foreign = await db_session.scalar(select(POI.embedding).where(POI.slug == "plage-b"))
    assert own is not None
    assert foreign is None


# ------------------------------------------- recherche par mots-cles (sans provider reel)


async def test_text_search_ranks_by_matches_and_excludes_inactive(
    db_session, test_tenant
):
    db_session.add_all(
        [
            _poi(
                test_tenant, "a", "Plage de Tipaza",
                city="Tipaza", description="ruines romaines en bord de mer",
            ),
            _poi(
                test_tenant, "b", "Ruines romaines",
                city="Tipaza", description="site romain",
            ),
            _poi(
                test_tenant, "c", "Ruines inactives",
                description="ruines romaines en bord de mer", is_active=False,
            ),
        ]
    )
    await db_session.commit()

    results = await RAGService(db_session, test_tenant).search("ruines romaines mer")
    assert [r["name"] for r in results] == ["Plage de Tipaza", "Ruines romaines"]
    assert [r["score"] for r in results] == [3.0, 2.0]


async def test_text_search_respects_top_k(db_session, test_tenant):
    db_session.add_all(
        [_poi(test_tenant, f"p{i}", f"Plage numero {i}") for i in range(3)]
    )
    await db_session.commit()

    results = await RAGService(db_session, test_tenant).search("plage", top_k=2)
    assert len(results) == 2


async def test_text_search_without_match_returns_empty_list(db_session, test_tenant):
    db_session.add(_poi(test_tenant, "a", "Plage de Tipaza"))
    await db_session.commit()

    assert await RAGService(db_session, test_tenant).search("xyzzy") == []


async def test_index_without_real_provider_reports_error(db_session, test_tenant):
    """Garde explicite : pas de vrai provider -> refus, jamais de vecteurs simules."""
    db_session.add(_poi(test_tenant, "a", "Plage de Tipaza"))
    await db_session.commit()

    result = await RAGService(db_session, test_tenant).index_pois()
    assert result == {"indexed": 0, "error": rag_service.NO_PROVIDER_ERROR}

    stored = await db_session.scalar(select(POI.embedding).where(POI.slug == "a"))
    assert stored is None


async def test_search_without_real_provider_uses_keyword_fallback(db_session, test_tenant):
    db_session.add(_poi(test_tenant, "a", "Plage de Tipaza"))
    await db_session.commit()

    results = await RAGService(db_session, test_tenant).search("plage")
    assert [r["name"] for r in results] == ["Plage de Tipaza"]


# --------------------------------------- recherche vectorielle (faux provider)


async def test_vector_search_is_isolated_and_ranked(
    db_session, test_tenant, other_tenant, fake_provider
):
    db_session.add_all(
        [
            _poi(test_tenant, "plage-a", "Plage de Tipaza", description="sable et mer"),
            _poi(test_tenant, "ruines-a", "Ruines romaines", description="site antique"),
            _poi(test_tenant, "old", "Plage fermee", is_active=False),
            _poi(other_tenant, "plage-b", "Plage secrete", description="autre tenant"),
        ]
    )
    await db_session.commit()

    indexed_a = await RAGService(db_session, test_tenant).index_pois()
    indexed_b = await RAGService(db_session, other_tenant).index_pois()
    assert indexed_a == {"indexed": 2, "tenant": "test-tenant"}
    assert indexed_b == {"indexed": 1, "tenant": "other-tenant"}

    results = await RAGService(db_session, test_tenant).search("plage", top_k=5)
    names = [r["name"] for r in results]
    assert names == ["Plage de Tipaza", "Ruines romaines"]
    assert "Plage secrete" not in names
    assert results[0]["score"] == pytest.approx(1.0)
    assert results[1]["score"] == pytest.approx(0.0, abs=1e-6)


async def test_vector_search_ignores_pois_without_embedding(
    db_session, test_tenant, fake_provider
):
    db_session.add(_poi(test_tenant, "plage-a", "Plage de Tipaza"))
    await db_session.commit()
    await RAGService(db_session, test_tenant).index_pois()

    db_session.add(_poi(test_tenant, "plage-new", "Plage nouvelle"))
    await db_session.commit()

    results = await RAGService(db_session, test_tenant).search("plage")
    assert [r["name"] for r in results] == ["Plage de Tipaza"]


async def test_index_failure_reports_error_and_stores_nothing(
    db_session, test_tenant, broken_provider
):
    db_session.add(_poi(test_tenant, "a", "Plage de Tipaza"))
    await db_session.commit()

    result = await RAGService(db_session, test_tenant).index_pois()
    assert result["indexed"] == 0
    assert "API down" in result["error"]

    stored = await db_session.scalar(select(POI.embedding).where(POI.slug == "a"))
    assert stored is None


async def test_search_falls_back_to_text_search_when_embedding_fails(
    db_session, test_tenant, broken_provider
):
    db_session.add(_poi(test_tenant, "a", "Plage de Tipaza"))
    await db_session.commit()

    results = await RAGService(db_session, test_tenant).search("plage")
    assert [r["name"] for r in results] == ["Plage de Tipaza"]


async def test_search_failure_logs_a_warning(db_session, test_tenant, broken_provider, caplog):
    db_session.add(_poi(test_tenant, "a", "Plage de Tipaza"))
    await db_session.commit()

    with caplog.at_level(logging.WARNING, logger="app.services.rag_service"):
        await RAGService(db_session, test_tenant).search("plage")

    assert any("falling back to keyword search" in r.message for r in caplog.records)
