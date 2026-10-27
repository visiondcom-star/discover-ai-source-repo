"""Factory for instantiating the configured EmailProvider."""
from typing import Optional
from app.config import Settings, get_settings
from app.services.email.base import EmailProvider
from app.services.email.console_provider import ConsoleEmailProvider
from app.services.email.resend_provider import ResendEmailProvider


def get_email_provider(settings: Optional[Settings] = None) -> EmailProvider:
    """Return configured email provider instance based on EMAIL_PROVIDER."""
    s = settings or get_settings()
    provider_name = (s.EMAIL_PROVIDER or "console").strip().lower()

    if provider_name == "console":
        return ConsoleEmailProvider()

    if provider_name == "resend":
        return ResendEmailProvider(
            api_key=s.RESEND_API_KEY,
            timeout_seconds=float(s.EMAIL_HTTP_TIMEOUT_SECONDS),
        )

    raise ValueError(f"Unknown EMAIL_PROVIDER: '{provider_name}'. Supported: 'console', 'resend'.")
