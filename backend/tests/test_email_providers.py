"""Unit tests for EmailProvider, ConsoleEmailProvider, ResendEmailProvider, and factory."""
import pytest
import httpx
from app.config import Settings
from app.services.email import (
    EmailMessage,
    EmailSendError,
    get_email_provider,
)
from app.services.email.console_provider import ConsoleEmailProvider
from app.services.email.resend_provider import ResendEmailProvider


@pytest.fixture
def sample_message():
    return EmailMessage(
        to="traveler@example.com",
        subject="Réservation confirmée",
        text="Votre réservation a été confirmée.",
        from_address="noreply@discoverai.local",
        from_name="Discover AI",
        reply_to="support@discoverai.local",
    )


@pytest.mark.asyncio
async def test_console_provider(sample_message, caplog):
    import logging
    caplog.set_level(logging.INFO)
    provider = ConsoleEmailProvider()
    assert provider.supports_idempotency is True

    result = await provider.send(sample_message, idempotency_key="notif-123")
    assert result.provider_message_id is not None
    assert result.provider_message_id.startswith("console-")
    # Log must state "notif-123 envoyée" without message subject/body or recipient email
    assert "notif-123 envoyée" in caplog.text
    assert sample_message.text not in caplog.text


def test_resend_missing_api_key():
    with pytest.raises(ValueError, match="RESEND_API_KEY is required"):
        ResendEmailProvider(api_key="")


@pytest.mark.asyncio
async def test_resend_success(sample_message):
    idempotency_sent = None
    auth_sent = None

    def handler(request: httpx.Request):
        nonlocal idempotency_sent, auth_sent
        idempotency_sent = request.headers.get("Idempotency-Key")
        auth_sent = request.headers.get("Authorization")
        assert request.url == "https://api.resend.com/emails"
        return httpx.Response(200, json={"id": "re_abc123456"})

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as client:
        provider = ResendEmailProvider(api_key="re_secret_test", client=client)
        assert provider.supports_idempotency is True
        result = await provider.send(sample_message, idempotency_key="notif-key-777")
        assert result.provider_message_id == "re_abc123456"
        assert idempotency_sent == "notif-key-777"
        assert auth_sent == "Bearer re_secret_test"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "status,body,expected_retryable,expected_code",
    [
        (429, {"message": "Too many requests", "name": "rate_limit_exceeded"}, True, "rate_limited"),
        (500, {"message": "Internal error"}, True, "server_error"),
        (503, {"message": "Service unavailable"}, True, "server_error"),
        (409, {"message": "Concurrent requests", "name": "concurrent_idempotent_requests"}, True, "concurrent_conflict"),
        (409, {"message": "Idempotency key does not match", "name": "invalid_idempotent_request"}, False, "invalid_idempotent_request"),
        (400, {"message": "Invalid recipient email"}, False, "http_400"),
        (401, {"message": "Invalid API Key"}, False, "http_401"),
        (403, {"message": "Domain not verified"}, False, "http_403"),
        (422, {"message": "Unprocessable entity"}, False, "http_422"),
    ],
)
async def test_resend_error_classification(
    sample_message, status, body, expected_retryable, expected_code
):
    def handler(request: httpx.Request):
        return httpx.Response(status, json=body)

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as client:
        provider = ResendEmailProvider(api_key="re_secret_test", client=client)
        with pytest.raises(EmailSendError) as exc_info:
            await provider.send(sample_message, idempotency_key="notif-err-1")
        err = exc_info.value
        assert err.retryable is expected_retryable
        assert err.code == expected_code


@pytest.mark.asyncio
async def test_resend_timeout_and_network_error(sample_message):
    def timeout_handler(request: httpx.Request):
        raise httpx.ReadTimeout("Connection read timeout")

    transport = httpx.MockTransport(timeout_handler)
    async with httpx.AsyncClient(transport=transport) as client:
        provider = ResendEmailProvider(api_key="re_secret_test", client=client)
        with pytest.raises(EmailSendError) as exc_info:
            await provider.send(sample_message, idempotency_key="notif-timeout")
        assert exc_info.value.retryable is True
        assert exc_info.value.code == "timeout"

    def network_handler(request: httpx.Request):
        raise httpx.ConnectError("Connection refused")

    transport2 = httpx.MockTransport(network_handler)
    async with httpx.AsyncClient(transport=transport2) as client2:
        provider2 = ResendEmailProvider(api_key="re_secret_test", client=client2)
        with pytest.raises(EmailSendError) as exc_info2:
            await provider2.send(sample_message, idempotency_key="notif-network")
        assert exc_info2.value.retryable is True
        assert exc_info2.value.code == "network_error"


def test_factory():
    cfg_console = Settings(EMAIL_PROVIDER="console")
    p1 = get_email_provider(cfg_console)
    assert isinstance(p1, ConsoleEmailProvider)

    cfg_resend = Settings(EMAIL_PROVIDER="resend", RESEND_API_KEY="re_test_key")
    p2 = get_email_provider(cfg_resend)
    assert isinstance(p2, ResendEmailProvider)
    assert p2.api_key == "re_test_key"

    cfg_invalid = Settings(EMAIL_PROVIDER="unknown")
    with pytest.raises(ValueError, match="Unknown EMAIL_PROVIDER"):
        get_email_provider(cfg_invalid)
