"""Tests de test_connection : le SDK openai est simulé, aucun appel réseau réel."""
import uuid
from types import SimpleNamespace

import httpx
import pytest
import openai

import app.services.tenant_ai_config_service as svc
from app.services.credential_crypto import CredentialCrypto

TENANT = uuid.uuid4()
KEY = bytes(range(32))


def _http_error(exc_cls, status_code, message):
    """Construit une vraie exception openai typée, avec une réponse httpx minimale
    (les exceptions du SDK exigent response.request)."""
    request = httpx.Request("POST", "https://api.openai.com/v1/chat/completions")
    response = httpx.Response(status_code, request=request)
    return exc_cls(message, response=response, body=None)


class _ScalarResult:
    def __init__(self, value):
        self._value = value

    def scalar_one_or_none(self):
        return self._value


class FakeDB:
    def __init__(self, *results):
        self._results = list(results)

    async def execute(self, _stmt):
        return self._results.pop(0)


class FakeLLMProvider:
    def __init__(self, error=None, model="tenant-model"):
        self.error = error
        self._model = model
        self.calls = []

    async def complete(self, messages, temperature=0.7, max_tokens=800):
        self.calls.append((messages, temperature, max_tokens))
        if self.error:
            raise self.error
        return "pong"


@pytest.fixture
def crypto(monkeypatch):
    c = CredentialCrypto({1: KEY})
    monkeypatch.setattr(svc, "_get_crypto", lambda: c)
    return c


def _stored_credential(crypto, api_key="sk-good-key"):
    enc = crypto.encrypt(api_key, tenant_id=TENANT, provider="openai")
    return SimpleNamespace(provider="openai", encrypted_key=enc.token, key_version=enc.key_version)


async def test_no_credential_returns_no_credential_without_any_call(monkeypatch):
    db = FakeDB(_ScalarResult(None))
    result = await svc.test_connection(db, TENANT, "openai")
    assert result == {"provider": "openai", "connected": False, "reason": "no_credential", "model_tested": None}


async def test_successful_ping_marks_connected(monkeypatch, crypto):
    cred = _stored_credential(crypto)
    fake_provider = FakeLLMProvider(model="gpt-4o-mini")
    db = FakeDB(_ScalarResult(cred), _ScalarResult(None))  # credential, puis pas de config
    monkeypatch.setitem(svc._PROVIDER_BUILDERS, "openai", lambda key, model: fake_provider)

    result = await svc.test_connection(db, TENANT, "openai")

    assert result == {"provider": "openai", "connected": True, "reason": None, "model_tested": "gpt-4o-mini"}
    assert fake_provider.calls[0][2] == 1  # max_tokens=1 : le ping reste minimal


@pytest.mark.parametrize(
    "error,expected_reason",
    [
        (_http_error(openai.AuthenticationError, 401, "bad key"), "invalid_api_key"),
        (_http_error(openai.RateLimitError, 429, "quota"), "quota_exceeded"),
        (_http_error(openai.NotFoundError, 404, "no model"), "model_unavailable"),
        (_http_error(openai.PermissionDeniedError, 403, "nope"), "permission_denied"),
        (ValueError("anything else"), "unknown_error"),
    ],
)
async def test_provider_errors_are_classified_not_leaked(monkeypatch, crypto, error, expected_reason):
    cred = _stored_credential(crypto)
    fake_provider = FakeLLMProvider(error=error)
    db = FakeDB(_ScalarResult(cred), _ScalarResult(None))
    monkeypatch.setitem(svc._PROVIDER_BUILDERS, "openai", lambda key, model: fake_provider)

    result = await svc.test_connection(db, TENANT, "openai")

    assert result["connected"] is False
    assert result["reason"] == expected_reason
    # le texte brut de l'erreur (potentiel fragment de clé) ne doit jamais apparaître
    assert "bad key" not in str(result)


async def test_credential_of_another_tenant_cannot_be_read(monkeypatch, crypto):
    other = uuid.uuid4()
    enc = crypto.encrypt("sk-other", tenant_id=other, provider="openai")
    cred = SimpleNamespace(provider="openai", encrypted_key=enc.token, key_version=enc.key_version)
    db = FakeDB(_ScalarResult(cred))

    result = await svc.test_connection(db, TENANT, "openai")

    assert result == {
        "provider": "openai", "connected": False, "reason": "credential_unreadable", "model_tested": None,
    }


async def test_unsupported_provider_rejected_before_any_query():
    async def boom(_stmt):
        raise AssertionError("la base ne doit pas être interrogée")

    db = SimpleNamespace(execute=boom)
    with pytest.raises(svc.UnsupportedProviderError):
        await svc.test_connection(db, TENANT, "gemini")
