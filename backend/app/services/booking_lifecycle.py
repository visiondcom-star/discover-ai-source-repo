"""Expiration paresseuse des demandes de réservation en attente.

Une réservation `manual_confirm` passée en `requested` porte une échéance
(`respond_by`). Passé ce délai sans réponse du partenaire, elle doit devenir
`expired`. On ne déploie pas de tâche planifiée à ce stade : l'expiration est
appliquée au fil de l'eau, à chaque lecture qui concerne le tenant. C'est
idempotent (un UPDATE qui ne touche aucune ligne si tout est à jour), donc
appelable sans risque depuis n'importe quel endpoint.

Une tâche planifiée (cron / Celery beat) pourra appeler `expire_overdue_requests`
plus tard pour purger en lot ; la signature est déjà compatible.
"""
from uuid import UUID

from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import Booking, POI, POIManager, Tenant, User, utcnow
from app.services.notification_service import create_notification


async def expire_overdue_requests(db: AsyncSession, tenant_id: UUID) -> int:
    """Fait passer `requested` → `expired` toute demande dont l'échéance est passée
    et notifie le voyageur ainsi que les gestionnaires du POI (une seule fois par réservation).

    Retourne le nombre de lignes modifiées (0 = rien à faire). Idempotent :
    rejouer la fonction immédiatement après ne change rien.
    """
    now = utcnow()
    # 1. Sélectionner les réservations expirées à mettre à jour
    query = (
        select(Booking)
        .where(
            and_(
                Booking.tenant_id == tenant_id,
                Booking.status == "requested",
                Booking.respond_by.is_not(None),
                Booking.respond_by < now,
            )
        )
        .options(selectinload(Booking.poi), selectinload(Booking.user))
        .with_for_update()
    )
    res = await db.execute(query)
    overdue_bookings = res.scalars().all()

    if not overdue_bookings:
        return 0

    tenant_res = await db.execute(select(Tenant).where(Tenant.id == tenant_id))
    tenant = tenant_res.scalar_one_or_none()

    for booking in overdue_bookings:
        booking.status = "expired"
        booking.updated_at = now

        payload = {"reason": "deadline_passed"}
        if booking.poi and booking.poi.name:
            payload["poi_name"] = booking.poi.name

        # Notifier le voyageur
        await create_notification(
            db=db,
            tenant_id=tenant_id,
            user_id=booking.user_id,
            type_="booking_expired",
            booking=booking,
            payload=payload,
            user=booking.user,
            tenant=tenant,
        )

        # Notifier les partenaires / gérants du POI
        mgrs_res = await db.execute(
            select(POIManager).where(
                and_(
                    POIManager.tenant_id == tenant_id,
                    POIManager.poi_id == booking.poi_id,
                )
            )
        )
        managers = mgrs_res.scalars().all()
        for mgr in managers:
            mgr_user_res = await db.execute(select(User).where(User.id == mgr.user_id))
            mgr_user = mgr_user_res.scalar_one_or_none()
            await create_notification(
                db=db,
                tenant_id=tenant_id,
                user_id=mgr.user_id,
                type_="booking_expired",
                booking=booking,
                payload=payload,
                user=mgr_user,
                tenant=tenant,
            )

    await db.commit()
    return len(overdue_bookings)
