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
