"""Service de gestion et de résolution des sources de recherche (ResearchSourceConfig)."""
import urllib.parse
from typing import List, Optional
from uuid import UUID

from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import ResearchSourceConfig, Tenant
from app.schemas import ResearchSourceConfigCreate, ResearchSourceConfigUpdate


class DuplicateSourceError(Exception):
    """Une source avec cette URL existe déjà pour ce tenant ou ce pays."""


def normalize_url(url: str) -> str:
    """Normalise une URL : hôte en minuscules, sans slash final ni fragment."""
    if not url:
        return ""
    parsed = urllib.parse.urlsplit(url.strip())
    scheme = parsed.scheme.lower()
    netloc = parsed.netloc.lower()
    path = parsed.path.rstrip("/") if parsed.path != "/" else ""
    query = parsed.query
    return urllib.parse.urlunsplit((scheme, netloc, path, query, ""))


async def resolve_sources(db: AsyncSession, tenant: Tenant) -> List[ResearchSourceConfig]:
    """Charge les sources applicables à un tenant.

    Règles :
    1. Charge les sources propres au tenant (tenant_id == tenant.id).
    2. Si tenant.country_code est défini, charge les sources du pays (tenant_id IS NULL).
    3. Les sources du tenant l'emportent sur celles du pays à URL normalisée identique,
       y compris quand elles sont enabled=False (le tenant désactive ainsi une source pays).
    4. Ne renvoie que les sources résultantes avec enabled=True.
    """
    tenant_sources_res = await db.execute(
        select(ResearchSourceConfig).where(ResearchSourceConfig.tenant_id == tenant.id)
    )
    tenant_sources = tenant_sources_res.scalars().all()
    tenant_by_url = {normalize_url(s.url): s for s in tenant_sources}

    country_sources: List[ResearchSourceConfig] = []
    if tenant.country_code:
        country_sources_res = await db.execute(
            select(ResearchSourceConfig).where(
                and_(
                    ResearchSourceConfig.tenant_id.is_(None),
                    ResearchSourceConfig.country_code == tenant.country_code,
                )
            )
        )
        country_sources = country_sources_res.scalars().all()

    resolved: List[ResearchSourceConfig] = []
    for s in tenant_sources:
        if s.enabled:
            resolved.append(s)

    for s in country_sources:
        norm = normalize_url(s.url)
        if norm not in tenant_by_url:
            if s.enabled:
                resolved.append(s)

    return resolved


async def create_tenant_source(
    db: AsyncSession,
    tenant_id: UUID,
    data: ResearchSourceConfigCreate,
) -> ResearchSourceConfig:
    """Crée une nouvelle source pour un tenant spécifique."""
    norm_url = normalize_url(data.url)

    existing = await db.execute(
        select(ResearchSourceConfig).where(
            ResearchSourceConfig.tenant_id == tenant_id
        )
    )
    for s in existing.scalars().all():
        if normalize_url(s.url) == norm_url:
            raise DuplicateSourceError(f"Une source avec l'URL '{data.url}' existe déjà pour ce tenant.")

    source = ResearchSourceConfig(
        tenant_id=tenant_id,
        country_code=None,
        name=data.name,
        url=data.url,
        source_type=data.source_type,
        enabled=data.enabled,
        config=data.config,
    )
    db.add(source)
    await db.commit()
    await db.refresh(source)
    return source


async def create_country_source(
    db: AsyncSession,
    country_code: str,
    data: ResearchSourceConfigCreate,
) -> ResearchSourceConfig:
    """Crée une nouvelle source pour un pays (utilisable pour seed/scripts)."""
    norm_url = normalize_url(data.url)
    norm_country = country_code.strip().upper()

    existing = await db.execute(
        select(ResearchSourceConfig).where(
            and_(
                ResearchSourceConfig.tenant_id.is_(None),
                ResearchSourceConfig.country_code == norm_country,
            )
        )
    )
    for s in existing.scalars().all():
        if normalize_url(s.url) == norm_url:
            raise DuplicateSourceError(f"Une source avec l'URL '{data.url}' existe déjà pour le pays {norm_country}.")

    source = ResearchSourceConfig(
        tenant_id=None,
        country_code=norm_country,
        name=data.name,
        url=data.url,
        source_type=data.source_type,
        enabled=data.enabled,
        config=data.config,
    )
    db.add(source)
    await db.commit()
    await db.refresh(source)
    return source


async def list_tenant_sources(
    db: AsyncSession,
    tenant_id: UUID,
) -> List[ResearchSourceConfig]:
    """Liste toutes les sources configurées pour un tenant."""
    res = await db.execute(
        select(ResearchSourceConfig)
        .where(ResearchSourceConfig.tenant_id == tenant_id)
        .order_by(ResearchSourceConfig.created_at.asc())
    )
    return res.scalars().all()


async def get_tenant_source(
    db: AsyncSession,
    tenant_id: UUID,
    source_id: UUID,
) -> Optional[ResearchSourceConfig]:
    """Récupère une source par son id avec isolation stricte par tenant."""
    res = await db.execute(
        select(ResearchSourceConfig).where(
            and_(
                ResearchSourceConfig.id == source_id,
                ResearchSourceConfig.tenant_id == tenant_id,
            )
        )
    )
    return res.scalar_one_or_none()


async def update_tenant_source(
    db: AsyncSession,
    tenant_id: UUID,
    source_id: UUID,
    data: ResearchSourceConfigUpdate,
) -> Optional[ResearchSourceConfig]:
    """Met à jour une source avec isolation tenant et contrôle de doublon."""
    source = await get_tenant_source(db, tenant_id, source_id)
    if not source:
        return None

    update_dict = data.model_dump(exclude_unset=True)
    if "url" in update_dict and update_dict["url"] is not None:
        target_norm = normalize_url(update_dict["url"])
        existing = await db.execute(
            select(ResearchSourceConfig).where(
                and_(
                    ResearchSourceConfig.tenant_id == tenant_id,
                    ResearchSourceConfig.id != source_id,
                )
            )
        )
        for s in existing.scalars().all():
            if normalize_url(s.url) == target_norm:
                raise DuplicateSourceError(f"Une source avec l'URL '{update_dict['url']}' existe déjà.")

    for field, value in update_dict.items():
        setattr(source, field, value)

    await db.commit()
    await db.refresh(source)
    return source


async def delete_tenant_source(
    db: AsyncSession,
    tenant_id: UUID,
    source_id: UUID,
) -> bool:
    """Supprime une source avec isolation stricte par tenant."""
    source = await get_tenant_source(db, tenant_id, source_id)
    if not source:
        return False

    await db.delete(source)
    await db.commit()
    return True

