"""Abstract base for LLM providers - Prinzip 7: austauschbare Provider-Abstraktion.

Chaque appel renvoie, avec le résultat, les **métadonnées d'usage** (``TokenUsage``) et le modèle
**réellement servi** : c'est ce qui alimente le journal d'usage/facturation par tenant
(``TenantAIUsageLog``) sans que les services appelants connaissent le SDK du provider.
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Dict, List


@dataclass(frozen=True)
class TokenUsage:
    """Tokens consommés par un appel provider.

    ``cached_tokens`` est un sous-ensemble de ``prompt_tokens`` facturé moins cher quand le
    provider le rapporte (OpenAI : ``usage.prompt_tokens_details.cached_tokens``). Un provider
    qui ne fournit pas cette information laisse 0 — jamais None, pour que le calcul de coût et
    le journal d'usage restent simples.
    """
    prompt_tokens: int = 0
    completion_tokens: int = 0
    cached_tokens: int = 0

    @property
    def total_tokens(self) -> int:
        return self.prompt_tokens + self.completion_tokens


@dataclass(frozen=True)
class CompletionResult:
    """Réponse d'un appel texte (chat ou vision).

    ``model`` est le modèle **effectivement servi** (le provider peut résoudre un alias ou
    basculer sur une autre version), pas celui demandé : c'est lui qui est facturé et journalisé.
    """
    text: str
    model: str
    usage: TokenUsage = field(default_factory=TokenUsage)


@dataclass(frozen=True)
class EmbeddingResult:
    """Réponse d'un appel d'embedding : le vecteur, le modèle servi et l'usage."""
    vector: List[float]
    model: str
    usage: TokenUsage = field(default_factory=TokenUsage)


class LLMProvider(ABC):
    #: Identifiant du provider — même clé que ``_PROVIDER_BUILDERS`` et ``TenantAICredential.provider``.
    name: str = "unknown"

    @property
    def configured_model(self) -> str:
        """Modèle demandé pour les complétions.

        Utile pour les lignes d'usage des appels **en échec** (aucune réponse, donc pas de
        modèle servi à journaliser). Le modèle réellement servi se lit dans ``CompletionResult``.
        """
        return "unknown"

    @abstractmethod
    async def complete(
        self,
        messages: List[Dict[str, str]],
        temperature: float = 0.7,
        max_tokens: int = 800,
    ) -> CompletionResult:
        raise NotImplementedError

    @abstractmethod
    async def embed(self, text: str) -> EmbeddingResult:
        """Return a vector embedding for the given text, for RAG similarity search."""
        raise NotImplementedError

    @abstractmethod
    async def identify_image(
        self,
        image_data_url: str,
        prompt: str,
        temperature: float = 0.2,
        max_tokens: int = 500,
    ) -> CompletionResult:
        """Identify the monument/site on a tourist image.

        ``image_data_url`` is a base64 data URL (e.g. ``data:image/jpeg;base64,...``).
        Returns (in ``text``) a JSON string (label/confidence/description/possible_pois keys)
        per the shared prompt contract, so the CV service can parse it uniformly across
        providers.
        """
        raise NotImplementedError
