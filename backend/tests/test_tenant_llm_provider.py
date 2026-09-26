"""Tests de get_tenant_llm_provider : la base est remplacée par des loaders simulés."""
import uuid
from types import SimpleNamespace

import pytest

from app.services import tenant_llm_provider as mod
from app.services.credential_crypto import CredentialCrypto, CredentialCryptoError
from app.services.llm_providers.mock_provider import MockProvider
from app.services.llm_providers.openai_provider import OpenAIProvider


KEY = bytes(range(32))
TENANT = uuid.uuid4()
DB = object()  # jamais utilisé : les loaders sont remplacés


def _config(**over):
    base = dict(
        primary_provider="openai",
        models={"chat": "tenant-chat-model"},
        enabled_features=["chat", "recommendation"],
    )
    base.update(over)
    return SimpleNamespace(**base)


def _settings(**over):
    base = dict(
        LLM_PROVIDER="openai",
        OPENAI_API_KEY="platform-key",
        OPENAI_MODEL="platform-model",
        EMBEDDING_MODEL="platform-embedding",
    )
    base.update(over)
    return SimpleNamespace(**base)


@pytest.fixture
def crypto(monkeypatch):
    c = CredentialCrypto({1: KEY})
    monkeypatch.setattr(mod, "_get_crypto", lambda: c)
    return c


@pytest.fixture
def recorded(monkeypatch):
    """Remplace le builder openai par un enregistreur."""
    calls = []

    def fake_builder(api_key, model):
        calls.append({"api_key": api_key, "model": model})
        return "provider-construit"

    monkeypatch.setitem(mod._PROVIDER_BUILDERS, "openai", fake_builder)
    return calls


def _patch_loaders(monkeypatch, config, credential=None):
    async def load_config(db, tenant_id):
        return config

    async def load_credential(db, tenant_id, provider):
        return credential

    monkeypatch.setattr(mod, "_load_config", load_config)
    monkeypatch.setattr(mod, "_load_credential", load_credential)


@pytest.fixture(autouse=True)
def quota(monkeypatch):
    """Le quota a ses propres tests (test_tenant_ai_quota_service) : ici il est isolé pour que
    la résolution de provider reste testable sans base réelle."""
    calls = []

    async def fake_check_quota(db, tenant_id):
        calls.append({"db": db, "tenant_id": tenant_id})

    monkeypatch.setattr(mod, "check_quota", fake_check_quota)
    return calls


async def test_no_config_falls_back_to_global_provider(monkeypatch):
    sentinel = object()
    monkeypatch.setattr(mod, "get_llm_provider", lambda: sentinel)
    _patch_loaders(monkeypatch, None)
    assert await mod.get_tenant_llm_provider(DB, TENANT, "chat") is sentinel


async def test_non_configurable_feature_rejected_before_any_query(monkeypatch):
    async def boom(*a, **k):
        raise AssertionError("la base ne doit pas être interrogée")

    monkeypatch.setattr(mod, "_load_config", boom)
    with pytest.raises(ValueError):
        await mod.get_tenant_llm_provider(DB, TENANT, "embeddings")


async def test_disabled_feature_raises(monkeypatch, recorded):
    _patch_loaders(monkeypatch, _config(enabled_features=["chat"]))
    with pytest.raises(mod.AIFeatureDisabledError):
        await mod.get_tenant_llm_provider(DB, TENANT, "research")
    assert recorded == []


async def test_unsupported_provider_has_no_silent_fallback(monkeypatch, recorded):
    _patch_loaders(monkeypatch, _config(primary_provider="anthropic"))
    with pytest.raises(mod.UnsupportedProviderError):
        await mod.get_tenant_llm_provider(DB, TENANT, "chat")
    assert recorded == []


async def test_byok_key_is_decrypted_and_model_taken_from_config(monkeypatch, crypto, recorded):
    enc = crypto.encrypt("sk-tenant-secret", tenant_id=TENANT, provider="openai")
    cred = SimpleNamespace(encrypted_key=enc.token, key_version=enc.key_version)
    _patch_loaders(monkeypatch, _config(), cred)

    result = await mod.get_tenant_llm_provider(DB, TENANT, "chat")

    assert result == "provider-construit"
    assert recorded == [{"api_key": "sk-tenant-secret", "model": "tenant-chat-model"}]


async def test_tenant_id_accepts_string_form(monkeypatch, crypto, recorded):
    enc = crypto.encrypt("sk-x", tenant_id=TENANT, provider="openai")
    cred = SimpleNamespace(encrypted_key=enc.token, key_version=enc.key_version)
    _patch_loaders(monkeypatch, _config(), cred)
    await mod.get_tenant_llm_provider(DB, str(TENANT).upper(), "chat")
    assert recorded[0]["api_key"] == "sk-x"


async def test_no_credential_uses_platform_key(monkeypatch, recorded):
    _patch_loaders(monkeypatch, _config(), None)
    await mod.get_tenant_llm_provider(DB, TENANT, "chat")
    assert recorded == [{"api_key": None, "model": "tenant-chat-model"}]


async def test_feature_without_model_uses_platform_model(monkeypatch, recorded):
    _patch_loaders(monkeypatch, _config(models={}), None)
    await mod.get_tenant_llm_provider(DB, TENANT, "chat")
    assert recorded == [{"api_key": None, "model": None}]


async def test_credential_of_another_tenant_cannot_be_used(monkeypatch, crypto, recorded):
    other = uuid.uuid4()
    enc = crypto.encrypt("sk-other-tenant", tenant_id=other, provider="openai")
    cred = SimpleNamespace(encrypted_key=enc.token, key_version=enc.key_version)
    _patch_loaders(monkeypatch, _config(), cred)
    with pytest.raises(CredentialCryptoError):
        await mod.get_tenant_llm_provider(DB, TENANT, "chat")
    assert recorded == []


async def test_master_key_only_needed_when_a_credential_exists(monkeypatch, recorded):
    def no_key():
        raise AssertionError("AI_MASTER_KEYS ne doit pas être requis sans credential")

    monkeypatch.setattr(mod, "_get_crypto", no_key)
    _patch_loaders(monkeypatch, _config(), None)
    await mod.get_tenant_llm_provider(DB, TENANT, "chat")


# --- quota (voir aussi test_tenant_ai_quota_service) -------------------------------------------

async def test_quota_is_checked_even_without_tenant_config(monkeypatch, quota):
    """Le repli plateforme n'exempte pas du quota : le budget est consommé pareil."""
    sentinel = object()
    monkeypatch.setattr(mod, "get_llm_provider", lambda: sentinel)
    _patch_loaders(monkeypatch, None)

    assert await mod.get_tenant_llm_provider(DB, TENANT, "chat") is sentinel
    assert quota == [{"db": DB, "tenant_id": TENANT}]


async def test_quota_receives_the_normalized_tenant_uuid(monkeypatch, quota):
    _patch_loaders(monkeypatch, _config(), None)
    await mod.get_tenant_llm_provider(DB, str(TENANT).upper(), "chat")
    assert [call["tenant_id"] for call in quota] == [TENANT]


async def test_quota_exceeded_propagates_before_reading_the_config(monkeypatch):
    async def boom(*a, **k):
        raise AssertionError("la config ne doit pas être lue si le quota est dépassé")

    monkeypatch.setattr(mod, "_load_config", boom)

    async def over(db, tenant_id):
        raise mod.QuotaExceededError(tenant_id, 50, 50)

    monkeypatch.setattr(mod, "check_quota", over)
    with pytest.raises(mod.QuotaExceededError):
        await mod.get_tenant_llm_provider(DB, TENANT, "chat")


async def test_quota_exceeded_builds_no_provider(monkeypatch, recorded):
    async def over(db, tenant_id):
        raise mod.QuotaExceededError(tenant_id, 50, 50)

    monkeypatch.setattr(mod, "check_quota", over)
    _patch_loaders(monkeypatch, _config())

    with pytest.raises(mod.QuotaExceededError):
        await mod.get_tenant_llm_provider(DB, TENANT, "chat")
    assert recorded == []


# --- builder openai (sans le faux builder) -------------------------------------------------

def test_build_openai_uses_tenant_key_model_and_platform_embedding(monkeypatch):
    monkeypatch.setattr(mod, "get_settings", lambda: _settings())
    p = mod._build_openai("sk-tenant", "tenant-model")
    assert isinstance(p, OpenAIProvider)
    assert p._model == "tenant-model"
    assert p._embedding_model == "platform-embedding"
    assert p._client.api_key == "sk-tenant"


def test_build_openai_falls_back_to_platform_key_and_model(monkeypatch):
    monkeypatch.setattr(mod, "get_settings", lambda: _settings())
    p = mod._build_openai(None, None)
    assert isinstance(p, OpenAIProvider)
    assert p._model == "platform-model"
    assert p._client.api_key == "platform-key"


def test_build_openai_without_any_key_returns_mock(monkeypatch):
    monkeypatch.setattr(mod, "get_settings", lambda: _settings(OPENAI_API_KEY=""))
    assert isinstance(mod._build_openai(None, None), MockProvider)
