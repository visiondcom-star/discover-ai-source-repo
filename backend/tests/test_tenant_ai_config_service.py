"""Tests de tenant_ai_config_service (sans base de données réelle)."""
import uuid
from types import SimpleNamespace

import pytest

import app.services.tenant_ai_config_service as svc
from app.services.credential_crypto import CredentialCrypto

TENANT = uuid.uuid4()
KEY = bytes(range(32))


class _ScalarResult:
    def __init__(self, value):
        self._value = value

    def scalar_one_or_none(self):
        return self._value

    def scalars(self):
        return SimpleNamespace(all=lambda: self._value)


class FakeDB:
    """db.execute renvoie les résultats fournis dans l'ordre. add/commit/refresh/delete
    sont enregistrés pour vérification, sans toucher à une vraie base."""

    def __init__(self, *results):
        self._results = list(results)
        self.added = []
        self.deleted = []
        self.commits = 0
        self.refreshed = []

    async def execute(self, _stmt):
        return self._results.pop(0)

    def add(self, obj):
        self.added.append(obj)

    async def commit(self):
        self.commits += 1

    async def refresh(self, obj):
        self.refreshed.append(obj)

    async def delete(self, obj):
        self.deleted.append(obj)


@pytest.fixture(autouse=True)
def crypto(monkeypatch):
    c = CredentialCrypto({1: KEY})
    monkeypatch.setattr(svc, "_get_crypto", lambda: c)
    return c


# --- upsert_config -------------------------------------------------------------------------

async def test_upsert_config_creates_when_none_exists():
    db = FakeDB(_ScalarResult(None))
    result = await svc.upsert_config(
        db, TENANT,
        primary_provider="openai", fallback_provider=None,
        models={"chat": "gpt-x"}, default_params={"temperature": 0.5},
        enabled_features=["chat"], monthly_spend_limit_usd=None,
    )
    assert result in db.added
    assert db.commits == 1
    assert result.primary_provider == "openai"
    assert result.models == {"chat": "gpt-x"}


async def test_upsert_config_updates_existing_without_re_adding():
    existing = SimpleNamespace(primary_provider="openai", models={}, tenant_id=TENANT)
    db = FakeDB(_ScalarResult(existing))
    result = await svc.upsert_config(
        db, TENANT,
        primary_provider="openai", fallback_provider="openai",
        models={"research": "gpt-y"}, default_params={},
        enabled_features=["research"], monthly_spend_limit_usd=50,
    )
    assert result is existing
    assert db.added == []  # pas de doublon
    assert result.enabled_features == ["research"]
    assert result.monthly_spend_limit_usd == 50


async def test_upsert_config_rejects_unsupported_primary_provider():
    db = FakeDB()
    with pytest.raises(svc.UnsupportedProviderError):
        await svc.upsert_config(
            db, TENANT,
            primary_provider="anthropic", fallback_provider=None,
            models={}, default_params={}, enabled_features=[],
            monthly_spend_limit_usd=None,
        )
    assert db.commits == 0


async def test_upsert_config_rejects_unsupported_fallback_provider():
    db = FakeDB(_ScalarResult(None))
    with pytest.raises(svc.UnsupportedProviderError):
        await svc.upsert_config(
            db, TENANT,
            primary_provider="openai", fallback_provider="gemini",
            models={}, default_params={}, enabled_features=[],
            monthly_spend_limit_usd=None,
        )
    assert db.commits == 0


# --- credentials -----------------------------------------------------------------------------

async def test_upsert_credential_creates_and_encrypts(crypto):
    db = FakeDB(_ScalarResult(None))
    cred = await svc.upsert_credential(db, TENANT, "openai", "sk-abcd1234")

    assert cred in db.added
    assert db.commits == 1
    assert cred.provider == "openai"
    assert cred.key_last4 == "1234"
    assert cred.encrypted_key != "sk-abcd1234"
    # le token stocké se déchiffre bien avec le même tenant/provider
    plain = crypto.decrypt(cred.encrypted_key, key_version=cred.key_version, tenant_id=TENANT, provider="openai")
    assert plain == "sk-abcd1234"


async def test_upsert_credential_rotates_existing_and_sets_rotated_at():
    existing = SimpleNamespace(
        provider="openai", encrypted_key="old", key_version=1, key_last4="0000", rotated_at=None
    )
    db = FakeDB(_ScalarResult(existing))
    cred = await svc.upsert_credential(db, TENANT, "openai", "sk-newkey9999")

    assert cred is existing
    assert db.added == []
    assert cred.key_last4 == "9999"
    assert cred.rotated_at is not None


async def test_upsert_credential_rejects_unsupported_provider():
    db = FakeDB()
    with pytest.raises(svc.UnsupportedProviderError):
        await svc.upsert_credential(db, TENANT, "gemini", "sk-x")
    assert db.commits == 0


async def test_upsert_credential_rejects_empty_key():
    db = FakeDB()
    with pytest.raises(ValueError):
        await svc.upsert_credential(db, TENANT, "openai", "   ")
    assert db.commits == 0


async def test_list_credentials_never_exposes_encrypted_key_by_itself():
    creds = [SimpleNamespace(provider="openai", key_last4="1234", encrypted_key="tok")]
    db = FakeDB(_ScalarResult(creds))
    result = await svc.list_credentials(db, TENANT)
    assert result == creds  # le filtrage vers le schema de réponse est fait par l'endpoint


async def test_delete_credential_returns_true_when_found():
    existing = SimpleNamespace(provider="openai")
    db = FakeDB(_ScalarResult(existing))
    ok = await svc.delete_credential(db, TENANT, "openai")
    assert ok is True
    assert existing in db.deleted
    assert db.commits == 1


async def test_delete_credential_returns_false_when_not_found():
    db = FakeDB(_ScalarResult(None))
    ok = await svc.delete_credential(db, TENANT, "openai")
    assert ok is False
    assert db.deleted == []
    assert db.commits == 0
