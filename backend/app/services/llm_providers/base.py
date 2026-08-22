"""Abstract base for LLM providers - Prinzip 7: austauschbare Provider-Abstraktion."""
from abc import ABC, abstractmethod
from typing import Dict, List


class LLMProvider(ABC):
    @abstractmethod
    async def complete(
        self,
        messages: List[Dict[str, str]],
        temperature: float = 0.7,
        max_tokens: int = 800,
    ) -> str:
        raise NotImplementedError

    @abstractmethod
    async def embed(self, text: str) -> List[float]:
        """Return a vector embedding for the given text, for RAG similarity search."""
        raise NotImplementedError

    @abstractmethod
    async def identify_image(
        self,
        image_data_url: str,
        prompt: str,
        temperature: float = 0.2,
        max_tokens: int = 500,
    ) -> str:
        """Identify the monument/site on a tourist image.

        ``image_data_url`` is a base64 data URL (e.g. ``data:image/jpeg;base64,...``).
        Returns a JSON string (label/confidence/description/possible_pois keys) per
        the shared prompt contract, so the CV service can parse it uniformly across
        providers.
        """
        raise NotImplementedError
