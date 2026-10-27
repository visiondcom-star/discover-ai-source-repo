"""Resend email provider using HTTP API (https://api.resend.com/emails)."""
import email.utils
import json
import logging
from typing import Optional
import httpx

from app.services.email.base import EmailMessage, EmailProvider, EmailSendError, EmailSendResult

logger = logging.getLogger(__name__)


class ResendEmailProvider(EmailProvider):
    """Resend email adapter with HTTP idempotency and retry classification."""

    supports_idempotency: bool = True
    API_URL: str = "https://api.resend.com/emails"

    def __init__(
        self,
        api_key: str,
        timeout_seconds: float = 15.0,
        client: Optional[httpx.AsyncClient] = None,
    ) -> None:
        clean_key = (api_key or "").strip()
        if not clean_key:
            raise ValueError("RESEND_API_KEY is required when using the Resend email provider.")
        self.api_key = clean_key
        self.timeout_seconds = timeout_seconds
        self._client = client

    async def send(self, message: EmailMessage, idempotency_key: str) -> EmailSendResult:
        from_header = email.utils.formataddr((message.from_name or "", message.from_address))
        payload = {
            "from": from_header,
            "to": [message.to],
            "subject": message.subject,
            "text": message.text,
        }
        if message.reply_to:
            payload["reply_to"] = message.reply_to

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Idempotency-Key": idempotency_key,
            "Content-Type": "application/json",
        }

        should_close = False
        client = self._client
        if client is None:
            client = httpx.AsyncClient(timeout=self.timeout_seconds)
            should_close = True

        try:
            response = await client.post(self.API_URL, json=payload, headers=headers)
        except httpx.TimeoutException as exc:
            raise EmailSendError(
                f"Resend request timed out: {type(exc).__name__}",
                retryable=True,
                code="timeout",
            ) from exc
        except httpx.RequestError as exc:
            raise EmailSendError(
                f"Resend network error: {type(exc).__name__}",
                retryable=True,
                code="network_error",
            ) from exc
        finally:
            if should_close:
                await client.aclose()

        status = response.status_code

        # Parse response body for id or error details
        body = {}
        try:
            body = response.json()
        except Exception:
            pass

        if 200 <= status < 300:
            msg_id = body.get("id")
            return EmailSendResult(provider_message_id=str(msg_id) if msg_id else None)

        err_type = str(body.get("name") or body.get("type") or "").strip().lower()
        err_msg = str(body.get("message") or f"HTTP {status}").strip()

        # Classification des erreurs
        # 429 -> retryable
        if status == 429:
            raise EmailSendError(f"Resend rate limit exceeded: {err_msg}", retryable=True, code="rate_limited")

        # 5xx -> retryable
        if status >= 500:
            raise EmailSendError(f"Resend server error ({status}): {err_msg}", retryable=True, code="server_error")

        # 409 conflict
        if status == 409:
            if "concurrent_idempotent_requests" in err_type or "concurrent" in err_msg.lower():
                raise EmailSendError(f"Resend concurrent conflict: {err_msg}", retryable=True, code="concurrent_conflict")
            if "invalid_idempotent_request" in err_type:
                raise EmailSendError(f"Resend invalid idempotency key: {err_msg}", retryable=False, code="invalid_idempotent_request")
            # Autre 409 non concurrent -> non retryable
            raise EmailSendError(f"Resend conflict: {err_msg}", retryable=False, code="conflict")

        # Tout autre 4xx -> non retryable
        raise EmailSendError(f"Resend client error ({status}): {err_msg}", retryable=False, code=f"http_{status}")
