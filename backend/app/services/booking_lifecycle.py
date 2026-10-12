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

from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Booking, utcnow


async def expire_overdue_requests(db: AsyncSession, tenant_id: UUID) -> int:
    """Fait passer `requested` → `expired` toute demande dont l'échéance est passée.

    Retourne le nombre de lignes modifiées (0 = rien à faire). Idempotent :
    rejouer la fonction immédiatement après ne change rien.
    """
    result = await db.execute(
        update(Booking)
        .where(
            Booking.tenant_id == tenant_id,
            Booking.status == "requested",
            Booking.respond_by.is_not(None),
            Booking.respond_by < utcnow(),
        )
        .values(status="expired", updated_at=utcnow())
    )
    # Le commit est fait ici (et non laissé à l'appelant) pour qu'un simple GET
    # persiste l'expiration. C'est sans danger pour les objets déjà chargés :
    # le sessionmaker applicatif est en `expire_on_commit=False`, donc aucune
    # relation/attribut ORM n'est invalidé par ce commit (pas de rechargement
    # lazy, donc pas de `MissingGreenlet`).
    await db.commit()
    return result.rowcount or 0
