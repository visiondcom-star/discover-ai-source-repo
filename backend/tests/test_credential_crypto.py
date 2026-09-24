"""Tests unitaires (sans base de données) du chiffrement des credentials BYOK."""
import base64
import uuid

import pytest

from app.services.credential_crypto import CredentialCrypto, CredentialCryptoError, last4

KEY1 = bytes(range(32))
KEY2 = bytes(range(32, 64))
SECRET = "sk-test-1234567890abcdef"


@pytest.fixture
def crypto():
    return CredentialCrypto({1: KEY1})


def test_roundtrip(crypto):
    tenant = uuid.uuid4()
    enc = crypto.encrypt(SECRET, tenant_id=tenant, provider="openai")
    assert enc.key_version == 1
    assert crypto.decrypt(enc.token, key_version=1, tenant_id=tenant, provider="openai") == SECRET


def test_token_does_not_contain_plaintext(crypto):
    enc = crypto.encrypt(SECRET, tenant_id=uuid.uuid4(), provider="openai")
    assert SECRET not in enc.token
    assert SECRET.encode() not in base64.urlsafe_b64decode(enc.token)


def test_two_encryptions_differ(crypto):
    tenant = uuid.uuid4()
    a = crypto.encrypt(SECRET, tenant_id=tenant, provider="openai")
    b = crypto.encrypt(SECRET, tenant_id=tenant, provider="openai")
    assert a.token != b.token  # nonce aléatoire


def test_wrong_tenant_cannot_decrypt(crypto):
    enc = crypto.encrypt(SECRET, tenant_id=uuid.uuid4(), provider="openai")
    with pytest.raises(CredentialCryptoError):
        crypto.decrypt(enc.token, key_version=1, tenant_id=uuid.uuid4(), provider="openai")


def test_wrong_provider_cannot_decrypt(crypto):
    tenant = uuid.uuid4()
    enc = crypto.encrypt(SECRET, tenant_id=tenant, provider="openai")
    with pytest.raises(CredentialCryptoError):
        crypto.decrypt(enc.token, key_version=1, tenant_id=tenant, provider="gemini")


def test_tampered_token_is_rejected(crypto):
    tenant = uuid.uuid4()
    enc = crypto.encrypt(SECRET, tenant_id=tenant, provider="openai")
    raw = bytearray(base64.urlsafe_b64decode(enc.token))
    raw[-1] ^= 0x01
    tampered = base64.urlsafe_b64encode(bytes(raw)).decode()
    with pytest.raises(CredentialCryptoError):
        crypto.decrypt(tampered, key_version=1, tenant_id=tenant, provider="openai")


def test_garbage_token_is_rejected(crypto):
    with pytest.raises(CredentialCryptoError):
        crypto.decrypt("pas-du-base64!!", key_version=1, tenant_id=uuid.uuid4(), provider="openai")


def test_unknown_key_version(crypto):
    enc = crypto.encrypt(SECRET, tenant_id=uuid.uuid4(), provider="openai")
    with pytest.raises(CredentialCryptoError):
        crypto.decrypt(enc.token, key_version=9, tenant_id=uuid.uuid4(), provider="openai")


def test_rotation_moves_secret_to_active_key():
    tenant = uuid.uuid4()
    old = CredentialCrypto({1: KEY1})
    enc_v1 = old.encrypt(SECRET, tenant_id=tenant, provider="openai")

    both = CredentialCrypto({1: KEY1, 2: KEY2})
    assert both.active_version == 2
    # ancienne donnée toujours lisible pendant la transition
    assert both.decrypt(enc_v1.token, key_version=1, tenant_id=tenant, provider="openai") == SECRET

    enc_v2 = both.rotate(enc_v1.token, key_version=1, tenant_id=tenant, provider="openai")
    assert enc_v2.key_version == 2
    # la clé v1 peut alors être retirée
    only_v2 = CredentialCrypto({2: KEY2})
    assert only_v2.decrypt(enc_v2.token, key_version=2, tenant_id=tenant, provider="openai") == SECRET


def test_explicit_active_version():
    c = CredentialCrypto({1: KEY1, 2: KEY2}, active_version=1)
    assert c.active_version == 1


def test_key_must_be_32_bytes():
    with pytest.raises(CredentialCryptoError):
        CredentialCrypto({1: b"trop-court"})


def test_no_keys_configured():
    with pytest.raises(CredentialCryptoError):
        CredentialCrypto({})


def test_from_env_parses_versions():
    env = {"AI_MASTER_KEYS": f"1:{KEY1.hex()},2:{KEY2.hex()}"}
    c = CredentialCrypto.from_env(env)
    assert c.active_version == 2
    env["AI_ACTIVE_KEY_VERSION"] = "1"
    assert CredentialCrypto.from_env(env).active_version == 1


def test_from_env_missing_raises():
    with pytest.raises(CredentialCryptoError):
        CredentialCrypto.from_env({})


def test_from_env_invalid_format_does_not_leak_key():
    bad = "1:" + "zz" * 32
    with pytest.raises(CredentialCryptoError) as exc:
        CredentialCrypto.from_env({"AI_MASTER_KEYS": bad})
    assert bad not in str(exc.value)


def test_error_messages_never_contain_secret(crypto):
    tenant = uuid.uuid4()
    enc = crypto.encrypt(SECRET, tenant_id=tenant, provider="openai")
    with pytest.raises(CredentialCryptoError) as exc:
        crypto.decrypt(enc.token, key_version=1, tenant_id=uuid.uuid4(), provider="openai")
    assert SECRET not in str(exc.value)
    assert enc.token not in str(exc.value)


def test_last4():
    assert last4(SECRET) == "cdef"
