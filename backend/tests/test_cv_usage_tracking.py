"""Tests du suivi d'usage/quota dans CVService (sans base de données).

Symétriques à `test_chat_usage_tracking.py` :
1. Une identification réussie appelle `record_llm_call()` avec usage, modèle,
   latence >= 0 et feature="cv".
2. `QuotaExceededError` (levée par la résolution du provider, AVANT le try)
   remonte intacte : aucun `record_llm_call()` n'est appelé, aucun fallback.
3. Une erreur provider appelle `record_llm_call()` avec status="error" et
   error_code classifié, et l'API renvoie quand même le fallback normalisé.
"""
import json
import uuid
from types import SimpleNamespace

import pytest

from app.services import cv_service as cvs
from app.services.llm_providers.base import CompletionResult, TokenUsage
from app.services.tenant_ai_quota_service import QuotaExceededError

TENANT = SimpleNamespace(id=uuid.uuid4(), name="Testland", default_language="fr")
TEST_IMAGE = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9"

_IDENTIFICATION_JSON = json.dumps(
    {
        "label": "Monument historique",
        "confidence": 0.95,
        "description": "Un monument identifiable.",
        "possible_pois": ["Casbah d'Alger"],
    }
)


class FakeProvider:
    def __init__(self, reply=_IDENTIFICATION_JSON, error=None, model="gpt-4o"):
        self.reply = reply
        self.error = error
        self.name = "openai"
        self.configured_model = model

    async def identify_image(self, image_data_url, prompt, temperature=0.2, max_tokens=500):
        if self.error:
            raise self.error
        return CompletionResult(
            text=self.reply,
            model=self.configured_model,
            usage=TokenUsage(prompt_tokens=42, completion_tokens=18, cached_tokens=10),
        )


def _build_service(monkeypatch, provider=None, resolver_error=None):
    async def fake_resolver(db, tenant_id, feature):
        if resolver_error:
            raise resolver_error
        return provider

    recorded_calls = []

    async def fake_record_llm_call(db, tenant_id, **kwargs):
        recorded_calls.append({"tenant_id": tenant_id, **kwargs})

    monkeypatch.setattr(cvs, "get_tenant_llm_provider", fake_resolver)
    monkeypatch.setattr(cvs, "record_llm_call", fake_record_llm_call)

    svc = cvs.CVService(db=object(), tenant=TENANT)
    return svc, recorded_calls


async def test_cv_success_records_usage_and_quota(monkeypatch):
    provider = FakeProvider(model="gpt-4o")
    svc, calls = _build_service(monkeypatch, provider=provider)

    result = await svc.identify(TEST_IMAGE, mime_type="image/jpeg")

    assert result["label"] == "Monument historique"
    assert len(calls) == 1
    call = calls[0]
    assert call["tenant_id"] == TENANT.id
    assert call["feature"] == "cv"
    assert call["status"] == "success"
    assert call["model"] == "gpt-4o"
    # Tokens facturés : c'est le coût de cette ligne qui incrémente le compteur de quota.
    assert call["usage"].prompt_tokens == 42
    assert call["usage"].completion_tokens == 18
    assert call["latency_ms"] >= 0
    assert "error_code" not in call or call.get("error_code") is None


async def test_cv_quota_exceeded_propagates_and_records_nothing(monkeypatch):
    """La résolution du provider est hors du try : QuotaExceededError remonte
    intacte (l'endpoint la transformera en 4xx/5xx) et aucun usage n'est
    journalisé — l'appel n'a eu lieu auprès d'aucun provider."""
    quota_error = QuotaExceededError(TENANT.id, monthly_limit=50, current_usage=50)
    svc, calls = _build_service(monkeypatch, resolver_error=quota_error)

    with pytest.raises(QuotaExceededError):
        await svc.identify(TEST_IMAGE, mime_type="image/jpeg")

    assert calls == []


async def test_cv_provider_error_records_error_and_returns_fallback(monkeypatch):
    import httpx
    import openai

    req = httpx.Request("POST", "https://api.openai.com/v1/chat/completions")
    resp = httpx.Response(429, request=req)
    err = openai.RateLimitError("Quota exceeded", response=resp, body=None)

    provider = FakeProvider(error=err, model="gpt-4o")
    svc, calls = _build_service(monkeypatch, provider=provider)

    result = await svc.identify(TEST_IMAGE, mime_type="image/jpeg")

    # Le fallback normalisé est renvoyé quand même (contrat API stable).
    assert result["label"] == cvs._FALLBACK_IDENTIFICATION["label"]
    assert result["confidence"] == 0.90
    assert result["possible_pois"] == []

    # L'erreur provider est bien journalisée avec la catégorie stable.
    assert len(calls) == 1
    call = calls[0]
    assert call["tenant_id"] == TENANT.id
    assert call["feature"] == "cv"
    assert call["status"] == "error"
    assert call["error_code"] == "quota_exceeded"
    assert call["model"] == "gpt-4o"
    assert call["usage"].prompt_tokens == 0
    assert call["usage"].completion_tokens == 0
    assert call["latency_ms"] >= 0
