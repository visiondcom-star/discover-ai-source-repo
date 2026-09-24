"""Tests du branchement de ChatService sur get_tenant_llm_provider (sans base de données)."""
import uuid
from types import SimpleNamespace

import pytest

from app.services import chat_service as cs
from app.services.tenant_llm_provider import AIFeatureDisabledError, UnsupportedProviderError

TENANT = SimpleNamespace(id=uuid.uuid4(), name="Testland", default_language="fr")


class FakeProvider:
    def __init__(self, reply="Bonjour voyageur", error=None):
        self.reply = reply
        self.error = error
        self.calls = []

    async def complete(self, messages, temperature=0.7, max_tokens=800):
        self.calls.append(messages)
        if self.error:
            raise self.error
        return self.reply


def _build(monkeypatch, provider=None, resolver_error=None):
    seen = SimpleNamespace(resolver=[], rag=[], saved=[])

    async def fake_resolver(db, tenant_id, feature):
        seen.resolver.append((tenant_id, feature))
        if resolver_error:
            raise resolver_error
        return provider

    monkeypatch.setattr(cs, "get_tenant_llm_provider", fake_resolver)
    svc = cs.ChatService(db=object(), tenant=TENANT)

    async def get_history(user_id, limit=10):
        return []

    async def rag(message, limit=3):
        seen.rag.append(message)
        return ""

    async def save(user_id, role, content, context=None):
        seen.saved.append((role, content))

    monkeypatch.setattr(svc, "_get_history", get_history)
    monkeypatch.setattr(svc, "_get_rag_context", rag)
    monkeypatch.setattr(svc, "_save_message", save)
    return svc, seen


async def test_chat_uses_the_tenant_provider_for_the_chat_feature(monkeypatch):
    provider = FakeProvider(reply="Voici mes conseils")
    svc, seen = _build(monkeypatch, provider=provider)

    result = await svc.chat(user_id="u1", message="Que visiter ?")

    assert seen.resolver == [(TENANT.id, "chat")]
    assert result["message"] == "Voici mes conseils"
    assert len(provider.calls) == 1


async def test_completion_error_detail_is_never_returned_to_the_client(monkeypatch):
    provider = FakeProvider(error=RuntimeError("Incorrect API key provided: sk-tenant-secret-1234"))
    svc, seen = _build(monkeypatch, provider=provider)

    result = await svc.chat(user_id="u1", message="Bonjour")

    assert "sk-tenant" not in result["message"]
    assert "Incorrect" not in result["message"]
    assert "problème technique" in result["message"]
    assert all("sk-tenant" not in content for _, content in seen.saved)


@pytest.mark.parametrize("error", [AIFeatureDisabledError("off"), UnsupportedProviderError("nope")])
async def test_config_errors_propagate_before_rag_and_before_any_write(monkeypatch, error):
    svc, seen = _build(monkeypatch, resolver_error=error)

    with pytest.raises(type(error)):
        await svc.chat(user_id="u1", message="Bonjour")

    assert seen.rag == []      # aucun embedding facturé
    assert seen.saved == []    # rien écrit en base
