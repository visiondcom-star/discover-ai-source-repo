"""Tests unitaires pour le moteur de tarification statique des modèles IA.

Vérifie :
1. Calcul du coût pour chat (prompt, completion, cached)
2. Embeddings (input seul)
3. Modèle inconnu -> coût nul + snapshot unpriced + alerte
4. Modèle mock/local -> coût nul sans warning
5. Déterminisme et précision décimale (ROUND_HALF_UP à 6 décimales)
6. Garde-fou de fraîcheur : les modèles par défaut du projet ont un tarif explicite
"""
from decimal import Decimal

from app.config import get_settings
from app.services.ai_pricing import (
    COST_QUANTUM,
    PRICING_TABLE_VERSION,
    PricedCall,
    estimate_cost_usd,
    price_call,
    resolve_price,
)
from app.services.llm_providers.base import TokenUsage


def test_resolve_price_known_model():
    p = resolve_price("gpt-4o")
    assert p is not None
    assert p.input_usd_per_1m == Decimal("2.50")
    assert p.output_usd_per_1m == Decimal("10.00")
    assert p.cached_input_usd_per_1m == Decimal("1.25")


def test_resolve_price_dated_variant_resolves():
    p = resolve_price("gpt-4o-2024-08-06")
    assert p is not None
    assert p.input_usd_per_1m == Decimal("2.50")


def test_resolve_price_case_insensitive():
    p = resolve_price("GPT-4O-MINI")
    assert p is not None
    assert p.input_usd_per_1m == Decimal("0.15")


def test_resolve_price_unknown_returns_none():
    assert resolve_price("totally-unknown-model-xyz") is None


def test_price_call_chat_with_cached_tokens():
    usage = TokenUsage(
        prompt_tokens=1000,
        completion_tokens=500,
        cached_tokens=400,
    )
    # gpt-4o :
    # non-cached input: (1000 - 400) * 2.50 / 1_000_000 = 600 * 2.50 / 1M = 0.001500
    # cached input: 400 * 1.25 / 1_000_000 = 0.000500
    # output: 500 * 10.00 / 1_000_000 = 0.005000
    # Total = 0.001500 + 0.000500 + 0.005000 = 0.007000
    priced = price_call("gpt-4o", usage)
    assert priced.cost_usd == Decimal("0.007000")
    assert priced.snapshot["priced"] is True
    assert priced.snapshot["table"] == PRICING_TABLE_VERSION
    assert priced.snapshot["prompt_tokens"] == 1000
    assert priced.snapshot["completion_tokens"] == 500
    assert priced.snapshot["cached_tokens"] == 400
    assert priced.snapshot["input_usd_per_1m"] == "2.50"


def test_price_call_embedding():
    usage = TokenUsage(prompt_tokens=10000, completion_tokens=0)
    # text-embedding-3-small : 10000 * 0.02 / 1_000_000 = 0.000200
    priced = price_call("text-embedding-3-small", usage)
    assert priced.cost_usd == Decimal("0.000200")
    assert priced.snapshot["priced"] is True


def test_price_call_unknown_model_defaults_to_zero_and_records_tokens():
    usage = TokenUsage(prompt_tokens=100, completion_tokens=50)
    priced = price_call("future-gpt-99", usage)
    assert priced.cost_usd == Decimal("0")
    assert priced.snapshot["priced"] is False
    assert priced.snapshot["reason"] == "unknown_model"
    assert priced.snapshot["prompt_tokens"] == 100
    assert priced.snapshot["completion_tokens"] == 50


def test_price_call_mock_model_costs_zero_and_marked_local():
    usage = TokenUsage(prompt_tokens=100, completion_tokens=50)
    priced = price_call("mock", usage)
    assert priced.cost_usd == Decimal("0")
    assert priced.snapshot["priced"] is True
    assert priced.snapshot["reason"] == "local_provider"


def test_price_call_cached_tokens_cannot_exceed_prompt_tokens():
    # Garde-fou : si le provider rapporte cached_tokens > prompt_tokens, on clamp.
    usage = TokenUsage(prompt_tokens=100, completion_tokens=0, cached_tokens=200)
    priced = price_call("gpt-4o-mini", usage)
    assert priced.snapshot["cached_tokens"] == 100
    # Tout est facturé au tarif cached (0.075 / 1M * 100 = 0.000008)
    expected = (Decimal("100") * Decimal("0.075") / Decimal("1000000")).quantize(COST_QUANTUM)
    assert priced.cost_usd == expected


def test_estimate_cost_usd_matches_price_call():
    usage = TokenUsage(prompt_tokens=500, completion_tokens=200)
    assert estimate_cost_usd("gpt-4o", usage) == price_call("gpt-4o", usage).cost_usd


def test_project_default_models_are_priced():
    """Garde-fou : si les defaults de config changent, ce test échoue pour rappeler
    d'ajouter leur tarif dans `ai_pricing.py`."""
    settings = get_settings()
    assert resolve_price(settings.OPENAI_MODEL) is not None, (
        f"OPENAI_MODEL='{settings.OPENAI_MODEL}' non présent dans la table tarifaire"
    )
    assert resolve_price(settings.EMBEDDING_MODEL) is not None, (
        f"EMBEDDING_MODEL='{settings.EMBEDDING_MODEL}' non présent"
    )
