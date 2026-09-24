"""Chiffrement des credentials BYOK des tenants (AES-256-GCM).

- Clés maîtres versionnées (rotation possible sans tout rechiffrer d'un coup).
- AAD = "<tenant_id>:<provider>" : un secret copié d'une ligne à une autre
  (autre tenant, autre provider) ne se déchiffre plus.
- Aucune valeur secrète (clé maître, clair, chiffré) n'apparaît dans les messages d'erreur.

Configuration : variable d'environnement
    AI_MASTER_KEYS="1:<64 hex>,2:<64 hex>"   (la version la plus haute est active)
    AI_ACTIVE_KEY_VERSION="2"                (optionnel, pour forcer la version active)
Générer une clé : python -c "import secrets; print(secrets.token_hex(32))"
"""
from __future__ import annotations

import base64
import binascii
import os
from dataclasses import dataclass
from typing import Dict, Mapping, Optional

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM


class CredentialCryptoError(Exception):
    """Erreur de chiffrement/déchiffrement. Ne contient jamais de secret."""


@dataclass(frozen=True)
class EncryptedSecret:
    token: str  # base64url(nonce || ciphertext+tag)
    key_version: int


class CredentialCrypto:
    NONCE_SIZE = 12
    KEY_SIZE = 32

    def __init__(self, keys: Mapping[int, bytes], active_version: Optional[int] = None):
        if not keys:
            raise CredentialCryptoError("Aucune clé maître configurée (AI_MASTER_KEYS).")
        for version, key in keys.items():
            if len(key) != self.KEY_SIZE:
                raise CredentialCryptoError(
                    f"La clé maître v{version} doit faire {self.KEY_SIZE} octets (64 caractères hex)."
                )
        self._keys: Dict[int, bytes] = dict(keys)
        self._active = active_version if active_version is not None else max(self._keys)
        if self._active not in self._keys:
            raise CredentialCryptoError(f"Version de clé active inconnue : v{self._active}.")

    @classmethod
    def from_env(cls, env: Optional[Mapping[str, str]] = None) -> "CredentialCrypto":
        env = os.environ if env is None else env
        raw = env.get("AI_MASTER_KEYS", "")
        keys: Dict[int, bytes] = {}
        for part in (p.strip() for p in raw.split(",")):
            if not part:
                continue
            version, _, hex_key = part.partition(":")
            try:
                keys[int(version)] = bytes.fromhex(hex_key)
            except ValueError:
                raise CredentialCryptoError(
                    "Format AI_MASTER_KEYS invalide (attendu '1:<64 hex>,2:<64 hex>')."
                ) from None
        active_raw = env.get("AI_ACTIVE_KEY_VERSION")
        try:
            active = int(active_raw) if active_raw else None
        except ValueError:
            raise CredentialCryptoError("AI_ACTIVE_KEY_VERSION doit être un entier.") from None
        return cls(keys, active)

    @property
    def active_version(self) -> int:
        return self._active

    @staticmethod
    def _aad(tenant_id: object, provider: str) -> bytes:
        return f"{tenant_id}:{provider}".encode("utf-8")

    def encrypt(self, plaintext: str, *, tenant_id: object, provider: str) -> EncryptedSecret:
        nonce = os.urandom(self.NONCE_SIZE)
        ciphertext = AESGCM(self._keys[self._active]).encrypt(
            nonce, plaintext.encode("utf-8"), self._aad(tenant_id, provider)
        )
        token = base64.urlsafe_b64encode(nonce + ciphertext).decode("ascii")
        return EncryptedSecret(token=token, key_version=self._active)

    def decrypt(self, token: str, *, key_version: int, tenant_id: object, provider: str) -> str:
        key = self._keys.get(key_version)
        if key is None:
            raise CredentialCryptoError(f"Clé maître v{key_version} indisponible.")
        try:
            raw = base64.urlsafe_b64decode(token.encode("ascii"))
            nonce, ciphertext = raw[: self.NONCE_SIZE], raw[self.NONCE_SIZE :]
            plaintext = AESGCM(key).decrypt(nonce, ciphertext, self._aad(tenant_id, provider))
            return plaintext.decode("utf-8")
        except (InvalidTag, binascii.Error, ValueError, UnicodeError):
            raise CredentialCryptoError(
                "Impossible de déchiffrer le credential (clé, tenant ou provider incorrect, ou donnée altérée)."
            ) from None

    def rotate(self, token: str, *, key_version: int, tenant_id: object, provider: str) -> EncryptedSecret:
        """Rechiffre un secret avec la clé active (à appeler ligne par ligne lors d'une rotation)."""
        plaintext = self.decrypt(token, key_version=key_version, tenant_id=tenant_id, provider=provider)
        return self.encrypt(plaintext, tenant_id=tenant_id, provider=provider)


def last4(secret: str) -> str:
    """4 derniers caractères, pour l'affichage dans l'UI admin (jamais la clé entière)."""
    return secret[-4:]
