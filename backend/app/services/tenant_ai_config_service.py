"""Gestion admin de la configuration IA d'un tenant : config + clés BYOK (CRUD).

Couche service testable sans base réelle (les endpoints de tenants.py ne font
qu'appeler ces fonctions et gérer les codes HTTP). Le test de connexion à un
provider (health check) fait l'objet d'une étape séparée : un appel réseau réel
n'a pas sa place dans un simple enregistrement de configuration.
"""
from __future__ import annotations

import uuid
from typing import Iterable, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import TenantAIConfig, TenantAICredential
from app.services.credential_crypto import CredentialCrypto, CredentialCryptoError
from app.services.tenant_llm_provider import _PROVIDER_BUILDERS, _get_crypto


class UnsupportedProviderError(ValueError):
    """Le provider demandé n'a pas d'adaptateur (voir _PROVIDER_BUILDERS)."""


def _check_provider_supported(provider: str) -> None:
    if provider not in _PROVIDER_BUILDERS:
        raise UnsupportedProviderError(
            f"Provider IA non supporté : {provider!r} (supportés : {sorted(_PROVIDER_BUILDERS)})"
        )


async def get_config(db: AsyncSession, tenant_id: uuid.UUID) -> Optional[TenantAIConfig]:
    result = await db.execute(select(TenantAIConfig).where(TenantAIConfig.tenant_id == tenant_id))
    return result.scalar_one_or_none()


async def upsert_config(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    primary_provider: str,
    fallback_provider: Optional[str],
    models: dict,
    default_params: dict,
    enabled_features: Iterable[str],
    monthly_spend_limit_usd,
) -> TenantAIConfig:
    """Crée ou met à jour la ligne de config du tenant (unique par tenant_id)."""
    _check_provider_supported(primary_provider)
    if fallback_provider is not None:
        _check_provider_supported(fallback_provider)

    config = await get_config(db, tenant_id)
    if config is None:
        config = TenantAIConfig(tenant_id=tenant_id)
        db.add(config)

    config.primary_provider = primary_provider
    config.fallback_provider = fallback_provider
    config.models = dict(models)  # déclenche la validation @validates("models")
    config.default_params = dict(default_params)
    config.enabled_features = list(enabled_features)
    config.monthly_spend_limit_usd = monthly_spend_limit_usd

    await db.commit()
    await db.refresh(config)
    return config


async def list_credentials(db: AsyncSession, tenant_id: uuid.UUID) -> list[TenantAICredential]:
    result = await db.execute(
        select(TenantAICredential).where(TenantAICredential.tenant_id == tenant_id)
    )
    return list(result.scalars().all())


async def upsert_credential(
    db: AsyncSession, tenant_id: uuid.UUID, provider: str, api_key: str
) -> TenantAICredential:
    """Chiffre et enregistre la clé BYOK d'un tenant pour un provider (une ligne par couple)."""
    _check_provider_supported(provider)
    if not api_key or not api_key.strip():
        raise ValueError("Clé API vide.")

    crypto: CredentialCrypto = _get_crypto()
    encrypted = crypto.encrypt(api_key, tenant_id=tenant_id, provider=provider)

    result = await db.execute(
        select(TenantAICredential).where(
            TenantAICredential.tenant_id == tenant_id,
            TenantAICredential.provider == provider,
        )
    )
    credential = result.scalar_one_or_none()
    is_rotation = credential is not None
    if credential is None:
        credential = TenantAICredential(tenant_id=tenant_id, provider=provider)
        db.add(credential)

    credential.encrypted_key = encrypted.token
    credential.key_version = encrypted.key_version
    credential.key_last4 = api_key[-4:]
    if is_rotation:
        from app.models import utcnow

        credential.rotated_at = utcnow()

    await db.commit()
    await db.refresh(credential)
    return credential


async def test_connection(db: AsyncSession, tenant_id: uuid.UUID, provider: str) -> dict:
    """Vérifie que la clé BYOK stockée pour ce provider fonctionne, avec un appel réel
    minimal (Provider Health Check, section 7 du document de conception).

    Ne teste que le credential déjà enregistré : si aucun n'existe pour ce provider,
    c'est à l'appelant de renvoyer 404, comme pour delete_credential (même sémantique).
    Ne renvoie jamais le texte brut de l'erreur fournisseur (il peut contenir un
    fragment de la clé rejetée) : seulement une classe d'erreur prédéfinie.
    """
    _check_provider_supported(provider)

    result = await db.execute(
        select(TenantAICredential).where(
            TenantAICredential.tenant_id == tenant_id,
            TenantAICredential.provider == provider,
        )
    )
    credential = result.scalar_one_or_none()
    if credential is None:
        return {"provider": provider, "connected": False, "reason": "no_credential", "model_tested": None}

    crypto: CredentialCrypto = _get_crypto()
    try:
        api_key = crypto.decrypt(
            credential.encrypted_key,
            key_version=credential.key_version,
            tenant_id=tenant_id,
            provider=provider,
        )
    except CredentialCryptoError:
        return {"provider": provider, "connected": False, "reason": "credential_unreadable", "model_tested": None}

    config = await get_config(db, tenant_id)
    model = (config.models or {}).get("chat") if config else None
    llm_provider = _PROVIDER_BUILDERS[provider](api_key, model)

    tested_model = getattr(llm_provider, "_model", model)
    reason = await _run_health_check(provider, llm_provider)
    return {
        "provider": provider,
        "connected": reason is None,
        "reason": reason,
        "model_tested": tested_model,
    }


async def _run_health_check(provider: str, llm_provider) -> Optional[str]:
    """Un appel réel minimal, classé en catégories stables (jamais le texte brut du
    fournisseur). Ajouter un provider ici = ajouter sa propre correspondance d'erreurs."""
    if provider == "openai":
        import openai

        try:
            await llm_provider.complete(
                [{"role": "user", "content": "ping"}], temperature=0, max_tokens=1
            )
            return None
        except openai.AuthenticationError:
            return "invalid_api_key"
        except openai.PermissionDeniedError:
            return "permission_denied"
        except openai.NotFoundError:
            return "model_unavailable"
        except openai.RateLimitError:
            return "quota_exceeded"
        except (openai.APIConnectionError, openai.APITimeoutError):
            return "network_error"
        except openai.APIStatusError:
            return "provider_error"
        except Exception:
            return "unknown_error"
    return "test_not_implemented_for_provider"


async def delete_credential(db: AsyncSession, tenant_id: uuid.UUID, provider: str) -> bool:
    result = await db.execute(
        select(TenantAICredential).where(
            TenantAICredential.tenant_id == tenant_id,
            TenantAICredential.provider == provider,
        )
    )
    credential = result.scalar_one_or_none()
    if credential is None:
        return False
    await db.delete(credential)
    await db.commit()
    return True
