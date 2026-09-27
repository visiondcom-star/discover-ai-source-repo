"""Tests pour le suivi d'usage dans RAGService (ingestion et recherche).

Vérifie que :
1. index_pois() enregistre un appel LLM pour chaque POI indexé avec la feature 'rag_ingestion'.
2. search() vectorielle enregistre un appel LLM avec la feature 'rag_search'.
3. Les erreurs d'embedding sont journalisées avec status='error' et error_code classifié.
"""
from types import SimpleNamespace
import uuid
from decimal import Decimal
import pytest

from app.models import POI
from app.services import rag_service as rs
from app.services.llm_providers.base import EmbeddingResult, TokenUsage


TENANT = SimpleNamespace(id=uuid.uuid4(), slug="testland", name="Testland")


class FakeEmbeddingProvider:
    def __init__(self, error=None, model="text-embedding-3-small"):
        self.error = error
        self.name = "openai"
        self.configured_model = model
        self.calls = []

    async def embed(self, text):
        self.calls.append(text)
        if self.error:
            raise self.error
        return EmbeddingResult(
            vector=[0.1] * 1536,
            model=self.configured_model,
            usage=TokenUsage(prompt_tokens=25, completion_tokens=0),
        )


def _poi(name="Casbah"):
    p = POI(
        id=uuid.uuid4(),
        tenant_id=TENANT.id,
        name=name,
        description="Desc",
        city="Alger",
        categories=["culture"],
        tags=["histoire"],
        is_active=True,
    )
    return p


class FakeSession:
    def __init__(self, pois=None):
        self._pois = pois or []
        self.committed = False
        self.rolled_back = False

    async def execute(self, stmt):
        class ScalarResult:
            def __init__(self, data):
                self._data = data

            def scalars(self):
                return self

            def all(self):
                return self._data

        return ScalarResult(self._pois)

    async def scalar(self, stmt):
        return 0.1

    async def commit(self):
        self.committed = True

    async def rollback(self):
        self.rolled_back = True


async def test_rag_index_pois_records_usage_per_poi(monkeypatch):
    provider = FakeEmbeddingProvider()
    recorded_calls = []

    async def fake_record_llm_call(db, tenant_id, **kwargs):
        recorded_calls.append({"tenant_id": tenant_id, **kwargs})

    monkeypatch.setattr(rs, "record_llm_call", fake_record_llm_call)
    pois = [_poi("Poi 1"), _poi("Poi 2")]
    db = FakeSession(pois)

    service = rs.RAGService(db=db, tenant=TENANT)
    service.provider = provider

    res = await service.index_pois()

    assert res["indexed"] == 2
    assert len(recorded_calls) == 2
    for c in recorded_calls:
        assert c["tenant_id"] == TENANT.id
        assert c["feature"] == "rag_ingestion"
        assert c["status"] == "success"
        assert c["model"] == "text-embedding-3-small"
        assert c["usage"].prompt_tokens == 25


async def test_rag_search_records_usage(monkeypatch):
    provider = FakeEmbeddingProvider()
    recorded_calls = []

    async def fake_record_llm_call(db, tenant_id, **kwargs):
        recorded_calls.append({"tenant_id": tenant_id, **kwargs})

    monkeypatch.setattr(rs, "record_llm_call", fake_record_llm_call)
    pois = [_poi("Poi 1")]
    db = FakeSession(pois)

    service = rs.RAGService(db=db, tenant=TENANT)
    service.provider = provider

    res = await service.search("musée", top_k=3)

    assert len(res) == 1
    assert len(recorded_calls) == 1
    call = recorded_calls[0]
    assert call["tenant_id"] == TENANT.id
    assert call["feature"] == "rag_search"
    assert call["status"] == "success"
    assert call["model"] == "text-embedding-3-small"


async def test_rag_embed_error_records_error_and_falls_back(monkeypatch):
    import openai
    import httpx

    req = httpx.Request("POST", "https://api.openai.com/v1/embeddings")
    resp = httpx.Response(401, request=req)
    err = openai.AuthenticationError("Invalid API key", response=resp, body=None)

    provider = FakeEmbeddingProvider(error=err)
    recorded_calls = []

    async def fake_record_llm_call(db, tenant_id, **kwargs):
        recorded_calls.append({"tenant_id": tenant_id, **kwargs})

    monkeypatch.setattr(rs, "record_llm_call", fake_record_llm_call)
    db = FakeSession([])

    service = rs.RAGService(db=db, tenant=TENANT)
    service.provider = provider

    # search() capture l'erreur et retombe sur _text_search
    results = await service.search("musée")
    assert results == []

    assert len(recorded_calls) == 1
    call = recorded_calls[0]
    assert call["status"] == "error"
    assert call["error_code"] == "invalid_api_key"
    assert call["usage"].prompt_tokens == 0
