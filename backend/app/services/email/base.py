"""Email abstraction layer: data structures, exceptions, and provider protocol."""
from dataclasses import dataclass
from typing import Optional, Protocol, runtime_checkable


@dataclass(frozen=True)
class EmailMessage:
    to: str
    subject: str
    text: str
    from_address: str
    from_name: str
    reply_to: Optional[str] = None


@dataclass(frozen=True)
class EmailSendResult:
    provider_message_id: Optional[str] = None


class EmailSendError(Exception):
    """Raised when an email provider fails to deliver a message."""

    def __init__(self, message: str, retryable: bool = False, code: Optional[str] = None) -> None:
        super().__init__(message)
        self.message = message
        self.retryable = retryable
        self.code = code


@runtime_checkable
class EmailProvider(Protocol):
    supports_idempotency: bool

    async def send(self, message: EmailMessage, idempotency_key: str) -> EmailSendResult:
        ...
