"""Factory to select the LLM provider based on configuration."""
from app.config import get_settings
from app.services.llm_providers.base import LLMProvider
from app.services.llm_providers.openai_provider import OpenAIProvider
from app.services.llm_providers.mock_provider import MockProvider

settings = get_settings()


def get_llm_provider() -> LLMProvider:
    """Return the configured LLM provider. Falls back to MockProvider without an API key."""
    if settings.OPENAI_API_KEY:
        return OpenAIProvider(api_key=settings.OPENAI_API_KEY, model=settings.OPENAI_MODEL)
    return MockProvider()
