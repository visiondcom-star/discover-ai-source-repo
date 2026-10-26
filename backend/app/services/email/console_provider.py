"""Console email provider: logs dispatch without sensitive payload."""
import logging
import uuid
from app.services.email.base import EmailMessage, EmailProvider, EmailSendResult

logger = logging.getLogger(__name__)


class ConsoleEmailProvider(EmailProvider):
    """Console email adapter.

    Journalise l'envoi sous la forme 'notification <id> envoyée' sans contenu
    ni clé secrète, pour tests et dev local.
    """

    supports_idempotency: bool = True

    async def send(self, message: EmailMessage, idempotency_key: str) -> EmailSendResult:
        logger.info("%s envoyée", idempotency_key)
        return EmailSendResult(provider_message_id=f"console-{uuid.uuid4().hex[:12]}")
