"""Tests d'intégration légers pour le suivi d'usage dans ChatService.

Vérifie :
1. Une complétion réussie appelle `record_llm_call()` avec usage, modèle, latence > 0.
2. Une erreur provider appelle `record_llm_call()` avec status='error' et error_code classifié.
3. Un échec de journalisation d'usage (ex: crash DB sur `record_llm_call`) ne fait pas échouer le chat.
"""
from types import SimpleNamespace
import uuid
import pytest

from app.models import Tenant
from app.services import chat_service as cs
from app.services.llm_providers.base import CompletionResult, TokenUsage


TENANT = SimpleNamespace(id=uuid.uuid4(), name="Testland", default_language="fr")


class FakeProvider:
    def __init__(self, reply="Bonjour voyageur", error=None, model="gpt-4o"):
        self.reply = reply
        self.error = error
        self.name = "openai"
        self.configured_model = model

    async def complete(self, messages, temperature=0.7, max_tokens=800):
        if self.error:
            raise self.error
        return CompletionResult(
            text=self.reply,
            model=self.configured_model,
            usage=TokenUsage(prompt_tokens=42, completion_tokens=18, cached_tokens=10),
        )


def _build_service(monkeypatch, provider=None):
    async def fake_resolver(db, tenant_id, feature):
        return provider

    recorded_calls = []

    async def fake_record_llm_call(db, tenant_id, **kwargs):
        recorded_calls.append({"tenant_id": tenant_id, **kwargs})

    async def get_history(user_id, limit=10):
        return []

    async def rag(message, limit=3):
        return ""

    async def save(user_id, role, content, context=None):
        pass

    monkeypatch.setattr(cs, "get_tenant_llm_provider", fake_resolver)
    monkeypatch.setattr(cs, "record_llm_call", fake_record_llm_call)

    svc = cs.ChatService(db=object(), tenant=TENANT)
    monkeypatch.setattr(svc, "_get_history", get_history)
    monkeypatch.setattr(svc, "_get_rag_context", rag)
    monkeypatch.setattr(svc, "_save_message", save)

    return svc, recorded_calls


async def test_chat_success_records_usage(monkeypatch):
    provider = FakeProvider(reply="Super réponse", model="gpt-4o")
    svc, calls = _build_service(monkeypatch, provider=provider)

    res = await svc.chat(user_id="user-123", message="Bonjour !")

    assert res["message"] == "Super réponse"
    assert len(calls) == 1
    call = calls[0]
    assert call["tenant_id"] == TENANT.id
    assert call["feature"] == "chat"
    assert call["status"] == "success"
    assert call["model"] == "gpt-4o"
    assert call["user_id"] == "user-123"
    assert call["usage"].prompt_tokens == 42
    assert call["usage"].completion_tokens == 18
    assert call["latency_ms"] >= 0


async def test_chat_error_records_zero_tokens_and_error_code(monkeypatch):
    import openai
    import httpx

    req = httpx.Request("POST", "https://api.openai.com/v1/chat/completions")
    resp = httpx.Response(429, request=req)
    err = openai.RateLimitError("Quota exceeded", response=resp, body=None)

    provider = FakeProvider(error=err, model="gpt-4o")
    svc, calls = _build_service(monkeypatch, provider=provider)

    res = await svc.chat(user_id="user-456", message="Bonjour !")

    # Le message au client est masqué
    assert "Je suis désolé" in res["message"]
    assert len(calls) == 1
    call = calls[0]
    assert call["tenant_id"] == TENANT.id
    assert call["feature"] == "chat"
    assert call["status"] == "error"
    assert call["error_code"] == "quota_exceeded"
    assert call["model"] == "gpt-4o"
    assert call["usage"].prompt_tokens == 0


async def test_chat_succeeds_even_if_usage_recording_throws(monkeypatch):
    provider = FakeProvider(reply="Super réponse")

    async def broken_record(*args, **kwargs):
        raise RuntimeError("DB connection dropped")

    svc, _ = _build_service(monkeypatch, provider=provider)
    monkeypatch.setattr(cs, "record_llm_call", broken_record)

    # Ne doit pas lever d'exception : record_llm_call est résilient ou ChatService l'est
    res = await svc.chat(user_id="user-789", message="Hello !")
    assert res["message"] == "Super réponse"
