"""Email service package."""
from app.services.email.base import EmailMessage, EmailProvider, EmailSendError, EmailSendResult
from app.services.email.factory import get_email_provider

__all__ = [
    "EmailMessage",
    "EmailProvider",
    "EmailSendError",
    "EmailSendResult",
    "get_email_provider",
]
