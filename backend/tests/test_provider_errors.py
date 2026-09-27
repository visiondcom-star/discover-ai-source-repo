"""Tests pour la classification hermétique des erreurs LLM.

Vérifie que :
1. Chaque exception OpenAI typique est catégorisée sans faire fuiter de clé d'API.
2. Les exceptions inconnues retombent sur "unknown_error".
3. Les providers non implémentés renvoient "unknown_error".
"""
import httpx
import openai
import pytest

from app.services.llm_providers.errors import classify_provider_error


def _dummy_response(status_code: int) -> httpx.Response:
    request = httpx.Request("POST", "https://api.openai.com/v1/chat/completions")
    return httpx.Response(status_code, request=request)


@pytest.mark.parametrize(
    "exc,expected",
    [
        (
            openai.AuthenticationError(
                "invalid api key: sk-secret123",
                response=_dummy_response(401),
                body=None,
            ),
            "invalid_api_key",
        ),
        (
            openai.PermissionDeniedError(
                "access denied",
                response=_dummy_response(403),
                body=None,
            ),
            "permission_denied",
        ),
        (
            openai.NotFoundError(
                "model not found: gpt-secret",
                response=_dummy_response(404),
                body=None,
            ),
            "model_unavailable",
        ),
        (
            openai.RateLimitError(
                "quota exceeded",
                response=_dummy_response(429),
                body=None,
            ),
            "quota_exceeded",
        ),
        (
            openai.APIConnectionError(request=httpx.Request("POST", "https://api.openai.com")),
            "network_error",
        ),
        (
            openai.APITimeoutError(request=httpx.Request("POST", "https://api.openai.com")),
            "network_error",
        ),
        (
            openai.InternalServerError(
                "provider down",
                response=_dummy_response(500),
                body=None,
            ),
            "provider_error",
        ),
        (RuntimeError("something unexpected"), "unknown_error"),
        (ValueError("bad json"), "unknown_error"),
    ],
)
def test_classify_openai_error(exc, expected):
    assert classify_provider_error(exc, provider="openai") == expected


def test_classify_unsupported_provider():
    assert classify_provider_error(RuntimeError("foo"), provider="unsupported") == "unknown_error"
