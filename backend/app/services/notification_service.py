"""Notification service: creation, deduplication and locale resolution."""
import logging
from typing import Any, Dict, Optional
from uuid import UUID

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Booking, Notification, Tenant, User
from app.services.notification_templates import render_notification

logger = logging.getLogger(__name__)


def resolve_locale(user: Optional[User], tenant: Optional[Tenant]) -> str:
    """Resolve locale with 3 fallback levels:

    1. user.locale (if set and not empty)
    2. tenant.default_language (if set and not empty)
    3. 'en'
    """
    if user and getattr(user, "locale", None):
        user_loc = str(user.locale).strip().lower()
        if user_loc:
            return user_loc

    if tenant and getattr(tenant, "default_language", None):
        tenant_lang = str(tenant.default_language).strip().lower()
        if tenant_lang:
            return tenant_lang

    return "en"


async def create_notification(
    db: AsyncSession,
    tenant_id: UUID,
    user_id: UUID,
    type_: str,
    booking: Optional[Booking] = None,
    payload: Optional[Dict[str, Any]] = None,
    user: Optional[User] = None,
    tenant: Optional[Tenant] = None,
    email: bool = True,
) -> Optional[Notification]:
    """Create a notification in the caller's session/transaction.

    - Resolves locale via resolve_locale(user, tenant)
    - If payload is None, defaults to {}
    - If email is False, email_status is set to 'skipped', otherwise defaults to 'pending'
    - Gracefully handles duplicates (unique index constraint on tenant_id, user_id, booking_id, type)
      using a SAVEPOINT (`begin_nested()`) so the outer transaction is not aborted.
    """
    resolved_loc = resolve_locale(user, tenant)
    norm_payload = dict(payload or {})

    notification = Notification(
        tenant_id=tenant_id,
        user_id=user_id,
        type=type_,
        booking_id=booking.id if booking else None,
        payload=norm_payload,
        locale=resolved_loc,
        email_status="pending" if email else "skipped",
    )

    try:
        async with db.begin_nested():
            db.add(notification)
            await db.flush()
        return notification
    except IntegrityError:
        # Savepoint rolled back automatically by context manager on exception.
        logger.info(
            "Ignored duplicate notification: tenant=%s user=%s booking=%s type=%s",
            tenant_id,
            user_id,
            booking.id if booking else None,
            type_,
        )
        return None
