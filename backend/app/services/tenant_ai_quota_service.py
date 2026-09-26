"""Gestion des quotas IA par tenant : lecture/reset de période, vérification, incrément atomique.

Couche service testable sans base réelle (même pattern que `tenant_ai_config_service.py`) :
les endpoints et les appelants (résolution de provider) ne font qu'appeler ces fonctions.

Trois responsabilités :

1. `get_or_create_quota_config` — une ligne par tenant, créée à la volée avec les défauts du
   modèle (50 USD/mois, alerte à 80 %, hard limit actif) : un tenant qui n'a jamais appelé
   l'IA n'a pas besoin d'être provisionné à l'avance.
2. `check_quota` — état courant du quota, avec reset *paresseux* de la période (pas de cron :
   la période expirée est remise à zéro à la première lecture qui suit son échéance). Lève
   `QuotaExceededError` si le hard limit est actif et dépassé.
3. `record_usage` — fonction critique : insère la ligne de journal ET incrémente le compteur
   dénormalisé dans la même transaction, via `UPDATE ... SET x = x + :cost` (jamais un
   read-then-write Python, qui perdrait des incréments en cas d'appels concurrents).
4. Création sans course : `get_or_create_quota_config` ne se contente pas d'un « SELECT puis
   INSERT » (deux appels IA simultanés du tout premier appel d'un tenant verraient tous deux
   « aucune ligne », et le second échouerait sur la clé primaire `tenant_id` — cassant l'appel
   IA de l'utilisateur) : un `IntegrityError` au commit signifie qu'une requête concurrente a
   créé la ligne entre-temps ; on annule la transaction avortée puis on relit la sienne.
"""
from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Optional

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import TenantAIQuotaConfig, TenantAIUsageLog, utcnow


class QuotaExceededError(Exception):
    """Levée quand hard_limit_enforced=True et current_period_usage >= monthly_limit."""
    def __init__(self, tenant_id: uuid.UUID, monthly_limit, current_usage):
        self.tenant_id = tenant_id
        self.monthly_limit = monthly_limit
        self.current_usage = current_usage
        super().__init__(f"Quota IA dépassé pour le tenant {tenant_id}")


async def get_or_create_quota_config(db: AsyncSession, tenant_id: uuid.UUID) -> TenantAIQuotaConfig:
    """Récupère la ligne de quota du tenant, ou la crée.

    La création est protégée contre les appels concurrents : si deux requêtes voient « aucune
    ligne » au même instant (tout premier appel IA d'un tenant), la seconde échoue sur la clé
    primaire `tenant_id`. On absorbe cet `IntegrityError` en relisant la ligne créée par l'autre
    requête, au lieu de casser l'appel IA de l'utilisateur.
    """
    result = await db.execute(
        select(TenantAIQuotaConfig).where(TenantAIQuotaConfig.tenant_id == tenant_id)
    )
    config = result.scalar_one_or_none()
    if config is not None:
        return config

    now = utcnow()
    config = TenantAIQuotaConfig(
        tenant_id=tenant_id,
        current_period_start=now,
        current_period_end=now + timedelta(days=30),
    )
    db.add(config)
    try:
        await db.commit()
    except IntegrityError:
        # Une requête concurrente a créé la ligne entre notre SELECT et notre INSERT.
        await db.rollback()
        result = await db.execute(
            select(TenantAIQuotaConfig).where(TenantAIQuotaConfig.tenant_id == tenant_id)
        )
        config = result.scalar_one()  # doit exister, sinon l'IntegrityError n'avait pas cette cause
    else:
        await db.refresh(config)
    return config


async def _reset_period_if_expired(db: AsyncSession, config: TenantAIQuotaConfig) -> TenantAIQuotaConfig:
    """Vérification paresseuse : pas de cron, la période se réinitialise à la première
    lecture/écriture qui survient après son échéance."""
    now = utcnow()
    if config.current_period_end <= now:
        config.current_period_start = now
        config.current_period_end = now + timedelta(days=30)
        config.current_period_usage = 0
        config.soft_limit_alert_sent = False
        await db.commit()
        await db.refresh(config)
    return config


async def check_quota(db: AsyncSession, tenant_id: uuid.UUID) -> TenantAIQuotaConfig:
    """Lève QuotaExceededError si le hard limit est actif et dépassé. Sinon renvoie
    la config à jour (période resetée si nécessaire) pour que l'appelant lise
    soft_limit_alert_sent / current_period_usage s'il veut alerter."""
    config = await get_or_create_quota_config(db, tenant_id)
    config = await _reset_period_if_expired(db, config)

    if config.hard_limit_enforced and config.current_period_usage >= config.monthly_limit:
        raise QuotaExceededError(tenant_id, config.monthly_limit, config.current_period_usage)

    return config


async def record_usage(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    provider: str,
    model: str,
    feature: str,
    prompt_tokens: int = 0,
    completion_tokens: int = 0,
    cached_tokens: int = 0,
    estimated_cost_usd,
    status: str = "success",
    error_code: Optional[str] = None,
    latency_ms: Optional[int] = None,
    request_id: Optional[uuid.UUID] = None,
    user_id: Optional[uuid.UUID] = None,
) -> TenantAIUsageLog:
    """Insère la ligne de log et incrémente current_period_usage dans la même transaction,
    via une expression SQL atomique (jamais un read-then-write Python — race condition sinon
    en cas d'appels concurrents sur le même tenant)."""
    log = TenantAIUsageLog(
        tenant_id=tenant_id,
        user_id=user_id,
        request_id=request_id,
        provider=provider,
        model=model,
        feature=feature,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        cached_tokens=cached_tokens,
        estimated_cost_usd=estimated_cost_usd,
        status=status,
        error_code=error_code,
        latency_ms=latency_ms,
    )
    db.add(log)

    await db.execute(
        update(TenantAIQuotaConfig)
        .where(TenantAIQuotaConfig.tenant_id == tenant_id)
        .values(current_period_usage=TenantAIQuotaConfig.current_period_usage + estimated_cost_usd)
    )

    await db.commit()
    await db.refresh(log)
    return log
