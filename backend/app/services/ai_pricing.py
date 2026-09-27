"""Estimation du coût d'un appel IA en USD, pour le journal d'usage (`TenantAIUsageLog`).

La table de tarifs vit dans le code, pas en base : la table `ai_model_pricing` du document de
gouvernance complet a été écartée, et une table statique versionnée reste auditable et testable
sans migration. Le tarif **appliqué** est recopié dans `TenantAIUsageLog.pricing_snapshot`, donc
une ligne ancienne reste explicable après un changement de prix.

Règles :
- modèle inconnu -> coût 0 et ``priced=False`` dans le snapshot (jamais d'exception) : un tarif
  manquant ne doit pas bloquer un appel. Les tokens restent en base, le coût est recalculable ;
- montants en ``Decimal`` (colonne ``Numeric(12, 6)``), arrondis à 6 décimales — pas de float ;
- ``cached_tokens`` facturés au tarif réduit quand le provider les rapporte, sinon au tarif input.

Limites assumées : tarifs publics standard d'OpenAI (pas de remise négociée, pas de batch) ; la
vision est facturée au tarif input, sans décomposition image ; mise à jour manuelle, avec bump de
``PRICING_TABLE_VERSION`` et vérification par ``test_ai_pricing.py`` que les modèles par défaut de
`config.py` sont bien tarifés.
"""
from __future__ import annotations

from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal
from typing import Dict, Optional

import structlog

from app.services.llm_providers.base import TokenUsage

logger = structlog.get_logger(__name__)

PRICING_TABLE_VERSION = "2026-09-26"

#: Providers locaux (mock) : aucun coût réel, donc aucun tarif manquant à signaler.
LOCAL_MODELS = frozenset({"mock", "mock-embedding"})

#: 6 décimales, comme la colonne ``estimated_cost_usd`` (Numeric(12, 6)).
COST_QUANTUM = Decimal("0.000001")
_TOKENS_PER_UNIT = Decimal(1_000_000)


@dataclass(frozen=True)
class ModelPrice:
    """Tarif public en USD pour 1 million de tokens."""
    input_usd_per_1m: Decimal
    output_usd_per_1m: Decimal
    cached_input_usd_per_1m: Optional[Decimal] = None


def _usd(value: str) -> Decimal:
    return Decimal(value)


#: Tarifs publics standard, en USD par million de tokens.
PRICES: Dict[str, ModelPrice] = {
    "gpt-4o": ModelPrice(_usd("2.50"), _usd("10.00"), _usd("1.25")),
    "gpt-4o-mini": ModelPrice(_usd("0.15"), _usd("0.60"), _usd("0.075")),
    "gpt-4-turbo": ModelPrice(_usd("10.00"), _usd("30.00")),
    "text-embedding-3-small": ModelPrice(_usd("0.02"), _usd("0.00")),
    "text-embedding-3-large": ModelPrice(_usd("0.13"), _usd("0.00")),
}


@dataclass(frozen=True)
class PricedCall:
    cost_usd: Decimal
    snapshot: dict


def resolve_price(model: str) -> Optional[ModelPrice]:
    """Tarif d'un modèle, par correspondance exacte puis par préfixe le plus long.

    Le préfixe couvre les modèles datés renvoyés par le provider
    (``gpt-4o-2024-08-06`` -> ``gpt-4o``), et le « plus long » évite que ``gpt-4o``
    capture ``gpt-4o-mini-2024-07-18`` (qui coûte 16 fois moins cher).
    Insensible à la casse.
    """
    key = (model or "").strip().lower()
    if key in PRICES:
        return PRICES[key]
    candidates = [name for name in PRICES if key.startswith(name)]
    return PRICES[max(candidates, key=len)] if candidates else None


def _usage_snapshot(model: str, usage: TokenUsage, **extra) -> dict:
    """Partie commune du snapshot : ce qui a été consommé + la version de la table tarifaire."""
    return {
        "model": model,
        "table": PRICING_TABLE_VERSION,
        "prompt_tokens": usage.prompt_tokens,
        "completion_tokens": usage.completion_tokens,
        "cached_tokens": usage.cached_tokens,
        **extra,
    }


def price_call(model: str, usage: TokenUsage) -> PricedCall:
    """Coût estimé + snapshot du tarif appliqué (une seule résolution de tarif)."""
    if model in LOCAL_MODELS:
        # Provider local (mock) : rien n'est facturé, ce n'est pas un tarif manquant.
        return PricedCall(
            cost_usd=Decimal("0"),
            snapshot=_usage_snapshot(model, usage, priced=True, reason="local_provider"),
        )

    price = resolve_price(model)
    if price is None:
        logger.warning("ai_pricing.unknown_model", model=model)
        return PricedCall(
            cost_usd=Decimal("0"),
            snapshot=_usage_snapshot(model, usage, priced=False, reason="unknown_model"),
        )

    prompt_tokens = max(usage.prompt_tokens, 0)
    # Garde-fou : un provider ne devrait jamais rapporter plus de tokens en cache que d'input.
    cached_tokens = min(max(usage.cached_tokens, 0), prompt_tokens)
    completion_tokens = max(usage.completion_tokens, 0)
    cached_price = (
        price.cached_input_usd_per_1m
        if price.cached_input_usd_per_1m is not None
        else price.input_usd_per_1m
    )

    cost = (
        (prompt_tokens - cached_tokens) * price.input_usd_per_1m
        + cached_tokens * cached_price
        + completion_tokens * price.output_usd_per_1m
    ) / _TOKENS_PER_UNIT

    return PricedCall(
        cost_usd=cost.quantize(COST_QUANTUM, rounding=ROUND_HALF_UP),
        snapshot=_usage_snapshot(
            model,
            TokenUsage(
                prompt_tokens=prompt_tokens,
                completion_tokens=completion_tokens,
                cached_tokens=cached_tokens,
            ),
            priced=True,
            input_usd_per_1m=str(price.input_usd_per_1m),
            output_usd_per_1m=str(price.output_usd_per_1m),
            cached_input_usd_per_1m=(
                str(price.cached_input_usd_per_1m)
                if price.cached_input_usd_per_1m is not None
                else None
            ),
        ),
    )


def estimate_cost_usd(model: str, usage: TokenUsage) -> Decimal:
    """Coût estimé, en USD (raccourci de `price_call` quand seul le montant intéresse)."""
    return price_call(model, usage).cost_usd
