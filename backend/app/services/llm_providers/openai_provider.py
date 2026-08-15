"""OpenAI LLM provider — the only place in the project importing the openai library."""
from typing import Dict, List

import openai  # type: ignore[import]

from app.services.llm_providers.base import LLMProvider


class OpenAIProvider(LLMProvider):
    def __init__(self, api_key: str, model: str, embedding_model: str = "text-embedding-3-small"):
        self._client = openai.AsyncOpenAI(api_key=api_key)
        self._model = model
        self._embedding_model = embedding_model

    async def complete(
        self,
        messages: List[Dict[str, str]],
        temperature: float = 0.7,
        max_tokens: int = 800,
    ) -> str:
        response = await self._client.chat.completions.create(
            model=self._model,
            messages=messages,
            temperature=temperature,
            max_tokens=max_tokens,
        )
        return response.choices[0].message.content

    async def embed(self, text: str) -> List[float]:
        response = await self._client.embeddings.create(
            input=[text],
            model=self._embedding_model,
        )
        return response.data[0].embedding
