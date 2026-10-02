"""Fermeture des jobs de recherche/collecte orphelins au démarrage du serveur."""
from datetime import datetime, timezone

from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import ResearchCollectionJob, ResearchJob

# Préfixe lu par le cooldown de manual_refresh : un job interrompu par un
# redémarrage n'est pas la faute de l'opérateur (même logique que quota_exceeded).
INTERRUPTED_PREFIX = "interrupted:"
ACTIVE_STATUSES = ("pending", "processing")


async def fail_orphan_jobs(db: AsyncSession) -> int:
    """Passe en `failed` tous les jobs encore actifs et renvoie leur nombre.

    À n'appeler qu'au démarrage d'un serveur à processus unique : à ce moment,
    aucune tâche de fond ne peut encore exécuter un job actif, donc ils sont
    tous orphelins (arrêt du serveur ou rechargement en pleine exécution).

    Mise à jour en ``UPDATE`` groupé et non boucle ORM : les jobs sont par
    définition rares au démarrage, et un statement par table évite de charger
    en mémoire des lignes qui ne servent qu'à être réécrites.
    """
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    message = f"{INTERRUPTED_PREFIX} le serveur a redémarré pendant l'exécution"
    total = 0
    for model in (ResearchJob, ResearchCollectionJob):
        result = await db.execute(
            update(model)
            .where(model.status.in_(ACTIVE_STATUSES))
            .values(status="failed", finished_at=now, error_message=message)
        )
        total += result.rowcount or 0
    await db.commit()
    return total