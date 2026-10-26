"""Background email worker for notifications: claiming, leasing, rendering, dispatching, and retrying."""
from datetime import datetime, timedelta
import logging
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, Field
from sqlalchemy import and_, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.models import Notification, Tenant, User, utcnow
from app.services.email.base import EmailMessage, EmailProvider, EmailSendError
from app.services.notification_templates import render_notification

logger = logging.getLogger(__name__)

# Délais de relance exponentielle par tentative
RETRY_DELAYS = {
    1: timedelta(minutes=1),
    2: timedelta(minutes=5),
    3: timedelta(minutes=30),
    4: timedelta(hours=6),
}
MAX_ATTEMPTS = 5
MAX_AGE_WINDOW = timedelta(hours=24)


class TenantEmailNotificationConfig(BaseModel):
    """Configuration e-mail d'un tenant validée depuis Tenant.config['notifications']['email']."""

    enabled: bool = True
    from_name: Optional[str] = None
    reply_to: Optional[str] = None


def get_tenant_email_config(tenant: Tenant) -> TenantEmailNotificationConfig:
    """Parse et valide Tenant.config['notifications']['email'] avec fallback gracieux."""
    raw = (tenant.config or {}).get("notifications", {}).get("email")
    if raw is None:
        return TenantEmailNotificationConfig(enabled=True)
    if isinstance(raw, dict):
        try:
            return TenantEmailNotificationConfig(**raw)
        except Exception as exc:
            logger.warning("Invalid tenant notification email config for %s: %s", tenant.id, exc)
            return TenantEmailNotificationConfig(enabled=True)
    return TenantEmailNotificationConfig(enabled=bool(raw))


def render_email(
    notification: Notification,
    user: User,
    tenant: Tenant,
    settings: Optional[Settings] = None,
) -> EmailMessage:
    """Render deterministic email from the stored notification row.

    - Utilise STRICTEMENT notification.locale (stockée à la création), jamais l'heure
      ni la locale actuelle de l'utilisateur.
    - Format texte brut.
    - Expéditeur = nom configuré dans Tenant.config['notifications']['email']['from_name']
      si présent, sinon settings.EMAIL_FROM_NAME ou nom du tenant.
    """
    s = settings or get_settings()
    tenant_cfg = get_tenant_email_config(tenant)

    # Expéditeur
    from_name = tenant_cfg.from_name or s.EMAIL_FROM_NAME or tenant.name
    from_address = s.EMAIL_FROM_ADDRESS
    reply_to = tenant_cfg.reply_to

    # Rendu du titre et du message
    stored_locale = notification.locale or "en"
    subject, body = render_notification(
        type_=notification.type,
        locale=stored_locale,
        payload=notification.payload,
    )

    return EmailMessage(
        to=user.email,
        subject=subject,
        text=body,
        from_address=from_address,
        from_name=from_name,
        reply_to=reply_to,
    )


async def claim_batch(
    session: AsyncSession,
    now: datetime,
    limit: int,
    lock_seconds: int = 600,
) -> List[UUID]:
    """Claim a batch of notifications for sending using SELECT FOR UPDATE SKIP LOCKED.

    Eligible rows:
    - email_status == 'pending' AND (next_attempt_at IS NULL OR next_attempt_at <= now)
    - OR email_status == 'sending' AND (locked_until IS NOT NULL AND locked_until <= now)
    """
    stmt = (
        select(Notification)
        .where(
            or_(
                and_(
                    Notification.email_status == "pending",
                    or_(
                        Notification.next_attempt_at.is_(None),
                        Notification.next_attempt_at <= now,
                    ),
                ),
                and_(
                    Notification.email_status == "sending",
                    Notification.locked_until.is_not(None),
                    Notification.locked_until <= now,
                ),
            )
        )
        .order_by(Notification.created_at.asc())
        .limit(limit)
        .with_for_update(skip_locked=True)
    )

    result = await session.execute(stmt)
    claimed_rows = result.scalars().all()

    valid_claimed_ids: List[UUID] = []
    locked_until_dt = now + timedelta(seconds=lock_seconds)

    for notif in claimed_rows:
        # Si une ligne reprise a déjà 5 tentatives ou plus, elle passe directement à failed
        if notif.email_attempts >= MAX_ATTEMPTS:
            notif.email_status = "failed"
            notif.locked_until = None
            notif.last_error = f"Max attempts ({notif.email_attempts}) exceeded on lease reclaim"
            continue

        notif.email_status = "sending"
        notif.locked_until = locked_until_dt
        notif.email_attempts = (notif.email_attempts or 0) + 1
        if notif.first_attempt_at is None:
            notif.first_attempt_at = now

        valid_claimed_ids.append(notif.id)

    await session.commit()
    return valid_claimed_ids


async def process_one(
    session: AsyncSession,
    notification_id: UUID,
    provider: EmailProvider,
    now: datetime,
    settings: Optional[Settings] = None,
) -> None:
    """Process a single claimed notification in 'sending' state.

    Toute écriture d'état se fait par UPDATE ... WHERE id = :id AND email_status = 'sending'.
    """
    s = settings or get_settings()

    # Charger la notification avec ses relations user et tenant
    res = await session.execute(
        select(Notification).where(
            and_(
                Notification.id == notification_id,
                Notification.email_status == "sending",
            )
        )
    )
    notif = res.scalar_one_or_none()
    if not notif:
        return

    # Charger user et tenant
    user_res = await session.execute(select(User).where(User.id == notif.user_id))
    user = user_res.scalar_one_or_none()

    tenant_res = await session.execute(select(Tenant).where(Tenant.id == notif.tenant_id))
    tenant = tenant_res.scalar_one_or_none()

    # 1. Vérification d'isolation tenant: user.tenant_id == notification.tenant_id
    if not user or user.tenant_id != notif.tenant_id:
        err = "User missing or does not belong to notification tenant"
        await session.execute(
            update(Notification)
            .where(
                and_(
                    Notification.id == notification_id,
                    Notification.email_status == "sending",
                )
            )
            .values(
                email_status="skipped",
                locked_until=None,
                last_error=err[:500],
            )
        )
        await session.commit()
        return

    # 2. Absence d'email ou tenant inactif / désactivé
    if not user.email or not tenant or not tenant.is_active:
        reason = "User email missing" if not (user and user.email) else "Tenant inactive"
        await session.execute(
            update(Notification)
            .where(
                and_(
                    Notification.id == notification_id,
                    Notification.email_status == "sending",
                )
            )
            .values(
                email_status="skipped",
                locked_until=None,
                last_error=reason[:500],
            )
        )
        await session.commit()
        return

    # 3. Validation de Tenant.config['notifications']['email']
    tenant_cfg = get_tenant_email_config(tenant)
    if not tenant_cfg.enabled:
        await session.execute(
            update(Notification)
            .where(
                and_(
                    Notification.id == notification_id,
                    Notification.email_status == "sending",
                )
            )
            .values(
                email_status="skipped",
                locked_until=None,
                last_error="Tenant email notifications disabled in config",
            )
        )
        await session.commit()
        return

    # 4. Préparation du message et envoi avec idempotency_key = f"notification-{id}"
    email_msg = render_email(notif, user, tenant, settings=s)
    idempotency_key = f"notification-{notif.id}"

    try:
        result = await provider.send(email_msg, idempotency_key=idempotency_key)
        # Succès -> sent, email_sent_at, provider_message_id, locked_until nul
        await session.execute(
            update(Notification)
            .where(
                and_(
                    Notification.id == notification_id,
                    Notification.email_status == "sending",
                )
            )
            .values(
                email_status="sent",
                email_sent_at=now,
                provider_message_id=result.provider_message_id,
                locked_until=None,
                last_error=None,
            )
        )
        await session.commit()
    except EmailSendError as exc:
        err_msg = (exc.message or str(exc))[:500]
        logger.warning(
            "Email send error for notification %s: retryable=%s code=%s",
            notif.id,
            exc.retryable,
            exc.code,
        )

        attempts = notif.email_attempts or 1
        first_attempt = notif.first_attempt_at or now

        # Erreur retryable
        if exc.retryable:
            # Vérifier plafond des tentatives et coupure 24h
            if attempts >= MAX_ATTEMPTS or (now - first_attempt) >= MAX_AGE_WINDOW:
                await session.execute(
                    update(Notification)
                    .where(
                        and_(
                            Notification.id == notification_id,
                            Notification.email_status == "sending",
                        )
                    )
                    .values(
                        email_status="failed",
                        locked_until=None,
                        last_error=f"Max attempts/age reached: {err_msg}"[:500],
                    )
                )
            else:
                delay = RETRY_DELAYS.get(attempts, timedelta(hours=6))
                next_dt = now + delay
                await session.execute(
                    update(Notification)
                    .where(
                        and_(
                            Notification.id == notification_id,
                            Notification.email_status == "sending",
                        )
                    )
                    .values(
                        email_status="pending",
                        next_attempt_at=next_dt,
                        locked_until=None,
                        last_error=err_msg[:500],
                    )
                )
        else:
            # Erreur non retryable -> failed
            await session.execute(
                update(Notification)
                .where(
                    and_(
                        Notification.id == notification_id,
                        Notification.email_status == "sending",
                    )
                )
                .values(
                    email_status="failed",
                    locked_until=None,
                    last_error=err_msg[:500],
                )
            )
        await session.commit()
    except Exception as exc:
        # Erreur inattendue -> failed
        err_msg = f"Unexpected error: {type(exc).__name__}: {str(exc)}"[:500]
        await session.execute(
            update(Notification)
            .where(
                and_(
                    Notification.id == notification_id,
                    Notification.email_status == "sending",
                )
            )
            .values(
                email_status="failed",
                locked_until=None,
                last_error=err_msg,
            )
        )
        await session.commit()
