"""Tests RAG : isolation entre tenants (principe 3 du CLAUDE.md) et chemins de recherche.

Deux chemins existent dans app/services/rag_service.py :
- recherche par mots-clés (sans clé OpenAI) ;
- recherche vectorielle pgvector (avec clé). Elle est testée ici avec un faux
  module `openai` aux embeddings déterministes, sans réseau. Couplage
  temporaire : il disparaîtra quand les embeddings passeront par le provider LLM.
"""
import sys
import types

import pytest
from sqlalchemy import select

import app.services.rag_service as rag_service
from app.models import POI
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
    """Vecteur unitaire déterministe : 'plage' -> e0, 'ruines' -> e1, sinon e2."""
    vec = [0.0] * 1536
    lowered = text.lower()
    if "plage" in lowered:
        vec[0] = 1.0
    elif "ruines" in lowered:
        vec[1] = 1.0
    else:
        vec[2] = 1.0
    return vec


class _FakeEmbeddings:
    def create(self, model, input):
        texts = input if isinstance(input, list) else [input]
        data = [
            types.SimpleNamespace(index=i, embedding=_fake_embedding(t))
            for i, t in enumerate(texts)
        ]
        return types.SimpleNamespace(data=data)


class _FakeOpenAI:
    def __init__(self, api_key=None):
        self.embeddings = _FakeEmbeddings()


class _BrokenOpenAI:
    def __init__(self, api_key=None):
        raise RuntimeError("API down")


@pytest.fixture(autouse=True)
def _no_openai_key(monkeypatch):
    """Tests hermétiques : jamais d'appel réseau, même si un .env contient une clé."""
    monkeypatch.setattr(rag_service.settings, "OPENAI_API_KEY", "")


@pytest.fixture
def fake_openai(monkeypatch):
    monkeypatch.setitem(sys.modules, "openai", types.SimpleNamespace(OpenAI=_FakeOpenAI))
    monkeypatch.setattr(rag_service.settings, "OPENAI_API_KEY", "test-key")


@pytest.fixture
def broken_openai(monkeypatch):
    monkeypatch.setitem(sys.modules, "openai", types.SimpleNamespace(OpenAI=_BrokenOpenAI))
    monkeypatch.setattr(rag_service.settings, "OPENAI_API_KEY", "test-key")


# ------------------------------------------------------------- endpoints


async def test_rag_search_never_returns_other_tenant_pois(
    client, auth_headers, other_admin_headers, test_tenant, other_tenant, db_session
):
    db_session.add_all(
        [
            _poi(test_tenant, "casbah-a", "Casbah d'Alger", description="Vieille médina"),
            _poi(other_tenant, "casbah-b", "Casbah de l'autre tenant", description="Médina"),
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


async def test_rag_index_endpoint_indexes_only_the_callers_tenant(
    client, auth_headers, test_tenant, other_tenant, db_session, fake_openai
):
    db_session.add_all(
        [
            _poi(test_tenant, "plage-a", "Plage de Tipaza"),
            _poi(other_tenant, "plage-b", "Plage secrète"),
        ]
    )
    await db_session.commit()

    response = await client.post(INDEX_URL, headers=auth_headers)
    assert response.status_code == 200, response.text
    assert response.json() == {"indexed": 1, "tenant": "test-tenant"}

    own = await db_session.scalar(select(POI.embedding).where(POI.slug == "plage-a"))
    foreign = await db_session.scalar(select(POI.embedding).where(POI.slug == "plage-b"))
    assert own is not None
    assert foreign is None


# ------------------------------------------- recherche par mots-clés (sans clé)


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
        [_poi(test_tenant, f"p{i}", f"Plage numéro {i}") for i in range(3)]
    )
    await db_session.commit()

    results = await RAGService(db_session, test_tenant).search("plage", top_k=2)
    assert len(results) == 2


async def test_text_search_without_match_returns_empty_list(db_session, test_tenant):
    db_session.add(_poi(test_tenant, "a", "Plage de Tipaza"))
    await db_session.commit()

    assert await RAGService(db_session, test_tenant).search("xyzzy") == []


async def test_index_without_api_key_reports_error(db_session, test_tenant):
    db_session.add(_poi(test_tenant, "a", "Plage de Tipaza"))
    await db_session.commit()

    result = await RAGService(db_session, test_tenant).index_pois()
    assert result["indexed"] == 0
    assert "not configured" in result["error"]

    stored = await db_session.scalar(select(POI.embedding).where(POI.slug == "a"))
    assert stored is None


# --------------------------------------- recherche vectorielle (faux openai)


async def test_vector_search_is_isolated_and_ranked(
    db_session, test_tenant, other_tenant, fake_openai
):
    db_session.add_all(
        [
            _poi(test_tenant, "plage-a", "Plage de Tipaza", description="sable et mer"),
            _poi(test_tenant, "ruines-a", "Ruines romaines", description="site antique"),
            _poi(test_tenant, "old", "Plage fermée", is_active=False),
            _poi(other_tenant, "plage-b", "Plage secrète", description="autre tenant"),
        ]
    )
    await db_session.commit()

    indexed_a = await RAGService(db_session, test_tenant).index_pois()
    indexed_b = await RAGService(db_session, other_tenant).index_pois()
    assert indexed_a == {"indexed": 2, "tenant": "test-tenant"}  # sans le POI inactif
    assert indexed_b == {"indexed": 1, "tenant": "other-tenant"}

    results = await RAGService(db_session, test_tenant).search("plage", top_k=5)
    names = [r["name"] for r in results]
    assert names == ["Plage de Tipaza", "Ruines romaines"]
    assert "Plage secrète" not in names  # jamais un POI d'un autre tenant
    assert results[0]["score"] == pytest.approx(1.0)
    assert results[1]["score"] == pytest.approx(0.0, abs=1e-6)


async def test_vector_search_ignores_pois_without_embedding(
    db_session, test_tenant, fake_openai
):
    db_session.add(_poi(test_tenant, "plage-a", "Plage de Tipaza"))
    await db_session.commit()
    await RAGService(db_session, test_tenant).index_pois()

    db_session.add(_poi(test_tenant, "plage-new", "Plage nouvelle"))  # pas indexé
    await db_session.commit()

    results = await RAGService(db_session, test_tenant).search("plage")
    assert [r["name"] for r in results] == ["Plage de Tipaza"]


async def test_index_failure_reports_error_and_stores_nothing(
    db_session, test_tenant, broken_openai
):
    db_session.add(_poi(test_tenant, "a", "Plage de Tipaza"))
    await db_session.commit()

    result = await RAGService(db_session, test_tenant).index_pois()
    assert result["indexed"] == 0
    assert "API down" in result["error"]

    stored = await db_session.scalar(select(POI.embedding).where(POI.slug == "a"))
    assert stored is None


async def test_search_falls_back_to_text_search_when_embedding_fails(
    db_session, test_tenant, broken_openai
):
    db_session.add(_poi(test_tenant, "a", "Plage de Tipaza"))
    await db_session.commit()

    results = await RAGService(db_session, test_tenant).search("plage")
    assert [r["name"] for r in results] == ["Plage de Tipaza"]
