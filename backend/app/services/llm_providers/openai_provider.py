"""OpenAI LLM provider — the only place in the project importing the openai library.

(`llm_providers/errors.py` l'importe aussi, paresseusement, pour classer les erreurs du SDK.)
"""
from typing import Dict, List, Optional

import openai  # type: ignore[import]

from app.services.llm_providers.base import (
    CompletionResult,
    EmbeddingResult,
    LLMProvider,
    TokenUsage,
)


class OpenAIProvider(LLMProvider):
    name = "openai"

    def __init__(self, api_key: str, model: str, embedding_model: str = "text-embedding-3-small"):
        self._client = openai.AsyncOpenAI(api_key=api_key)
        self._model = model
        self._embedding_model = embedding_model

    @property
    def configured_model(self) -> str:
        return self._model

    @staticmethod
    def _usage(raw: Optional[object]) -> TokenUsage:
        """Usage renvoyé par le SDK.

        ``cached_tokens`` vit dans ``prompt_tokens_details``, absent du typage d'openai 1.37 :
        on le lit défensivement (les modèles pydantic du SDK gardent les champs inconnus en
        « extra »), sans imposer une montée de version.
        """
        if raw is None:
            return TokenUsage()
        details = getattr(raw, "prompt_tokens_details", None)
        cached = getattr(details, "cached_tokens", None)
        if cached is None and isinstance(details, dict):
            cached = details.get("cached_tokens")
        return TokenUsage(
            prompt_tokens=getattr(raw, "prompt_tokens", 0) or 0,
            completion_tokens=getattr(raw, "completion_tokens", 0) or 0,
            cached_tokens=cached or 0,
        )

    async def complete(
        self,
        messages: List[Dict[str, str]],
        temperature: float = 0.7,
        max_tokens: int = 800,
    ) -> CompletionResult:
        response = await self._client.chat.completions.create(
            model=self._model,
            messages=messages,
            temperature=temperature,
            max_tokens=max_tokens,
        )
        return CompletionResult(
            text=response.choices[0].message.content,
            model=response.model or self._model,  # modèle servi (alias résolu par OpenAI)
            usage=self._usage(response.usage),
        )

    async def embed(self, text: str) -> EmbeddingResult:
        response = await self._client.embeddings.create(
            input=[text],
            model=self._embedding_model,
        )
        return EmbeddingResult(
            vector=response.data[0].embedding,
            model=response.model or self._embedding_model,
            usage=self._usage(getattr(response, "usage", None)),
        )

    async def identify_image(
        self,
        image_data_url: str,
        prompt: str,
        temperature: float = 0.2,
        max_tokens: int = 500,
    ) -> CompletionResult:
        response = await self._client.chat.completions.create(
            model=self._model,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": image_data_url}},
                    ],
                }
            ],
            response_format={"type": "json_object"},
            temperature=temperature,
            max_tokens=max_tokens,
        )
        return CompletionResult(
            text=response.choices[0].message.content,
            model=response.model or self._model,
            usage=self._usage(response.usage),
        )
