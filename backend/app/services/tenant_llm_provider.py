"""Résolution du LLMProvider d'un tenant : config IA + clé BYOK, avec repli sur la config globale.

Règles :
- Tenant SANS ligne `tenant_ai_configs`  -> comportement actuel inchangé (`get_llm_provider()` global).
- Tenant AVEC config :
    * la feature doit être activée pour lui (`enabled_features`) sinon AIFeatureDisabledError ;
    * son provider doit être supporté sinon UnsupportedProviderError. Pas de repli silencieux
      vers la clé plateforme : cela enverrait le trafic du tenant chez un autre fournisseur ;
    * clé BYOK déchiffrée si elle existe, sinon clé plateforme du même provider ;
    * modèle = celui choisi pour la feature, sinon le modèle plateforme.
- Le modèle d'embedding reste celui de la plateforme (jamais choisi par le tenant).
- La clé déchiffrée n'est jamais loggée ni renvoyée : elle n'existe que dans le provider construit.
"""
from __future__ import annotations

import functools
import uuid
from typing import Callable, Dict, Optional

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models import TENANT_CONFIGURABLE_FEATURES, TenantAIConfig, TenantAICredential
from app.services.credential_crypto import CredentialCrypto
from app.services.llm_providers.base import LLMProvider
from app.services.llm_providers.factory import get_llm_provider
from app.services.llm_providers.mock_provider import MockProvider
from app.services.llm_providers.openai_provider import OpenAIProvider

logger = structlog.get_logger(__name__)


class TenantAIError(Exception):
    """Base des erreurs de configuration IA d'un tenant."""


class AIFeatureDisabledError(TenantAIError):
    """La feature IA demandée n'est pas activée pour ce tenant."""


class UnsupportedProviderError(TenantAIError):
    """Le provider configuré pour ce tenant n'a pas d'adaptateur."""


def _build_openai(api_key: Optional[str], model: Optional[str]) -> LLMProvider:
    settings = get_settings()
    key = api_key or settings.OPENAI_API_KEY
    if not key:
        # Même comportement que la factory globale sans clé.
        logger.warning("tenant_ai.no_api_key_using_mock_provider")
        return MockProvider()
    return OpenAIProvider(
        api_key=key,
        model=model or settings.OPENAI_MODEL,
        embedding_model=settings.EMBEDDING_MODEL,
    )


# Ajouter un provider = ajouter une entrée ici (+ son adaptateur dans llm_providers/).
_PROVIDER_BUILDERS: Dict[str, Callable[[Optional[str], Optional[str]], LLMProvider]] = {
    "openai": _build_openai,
}


@functools.lru_cache(maxsize=1)
def _get_crypto() -> CredentialCrypto:
    return CredentialCrypto.from_env()


async def _load_config(db: AsyncSession, tenant_id: uuid.UUID) -> Optional[TenantAIConfig]:
    result = await db.execute(select(TenantAIConfig).where(TenantAIConfig.tenant_id == tenant_id))
    return result.scalar_one_or_none()


async def _load_credential(
    db: AsyncSession, tenant_id: uuid.UUID, provider: str
) -> Optional[TenantAICredential]:
    result = await db.execute(
        select(TenantAICredential).where(
            TenantAICredential.tenant_id == tenant_id,
            TenantAICredential.provider == provider,
        )
    )
    return result.scalar_one_or_none()


async def get_tenant_llm_provider(
    db: AsyncSession, tenant_id: object, feature: str
) -> LLMProvider:
    """Retourne le provider LLM à utiliser pour ce tenant et cette feature."""
    if feature not in TENANT_CONFIGURABLE_FEATURES:
        raise ValueError(
            f"Feature IA inconnue ou non configurable par tenant : {feature!r} "
            f"(autorisées : {list(TENANT_CONFIGURABLE_FEATURES)})"
        )
    # Normalisé : l'AAD du chiffrement repose sur la forme canonique de l'UUID.
    tenant_id = uuid.UUID(str(tenant_id))

    config = await _load_config(db, tenant_id)
    if config is None:
        return get_llm_provider()

    if feature not in (config.enabled_features or []):
        raise AIFeatureDisabledError(f"La feature IA {feature!r} n'est pas activée pour ce tenant.")

    provider_id = config.primary_provider
    builder = _PROVIDER_BUILDERS.get(provider_id)
    if builder is None:
        raise UnsupportedProviderError(f"Provider IA non supporté : {provider_id!r}.")

    api_key: Optional[str] = None
    credential = await _load_credential(db, tenant_id, provider_id)
    if credential is not None:
        api_key = _get_crypto().decrypt(
            credential.encrypted_key,
            key_version=credential.key_version,
            tenant_id=tenant_id,
            provider=provider_id,
        )

    model = (config.models or {}).get(feature)
    logger.info(
        "tenant_ai.provider_resolved",
        tenant_id=str(tenant_id),
        feature=feature,
        provider=provider_id,
        byok=credential is not None,
    )
    return builder(api_key, model)
