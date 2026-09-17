"""Tenant management endpoints."""
from typing import List
from datetime import datetime, timezone, timedelta
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Header, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models import Tenant, TenantCategory, ResearchJob
from app.schemas import (
    TenantCreate,
    TenantUpdate,
    TenantResponse,
    TenantCategoryCreate,
    TenantCategoryResponse,
    ResearchJobResponse,
    ResearchRunRequest,
)
from app.constants import RESEARCH_MANUAL_REFRESH_COOLDOWN_DAYS
from app.dependencies import get_current_admin

router = APIRouter()


@router.get("/current", response_model=TenantResponse)
async def get_current_tenant_config(
    x_tenant_slug: str = Header(default="algeria"),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Tenant).where(Tenant.slug == x_tenant_slug))
    tenant = result.scalar_one_or_none()
    if not tenant:
        raise HTTPException(status_code=404, detail="Tenant not found")
    return tenant


@router.get("/categories", response_model=List[TenantCategoryResponse])
async def list_tenant_categories(
    x_tenant_slug: str = Header(default="algeria"),
    db: AsyncSession = Depends(get_db),
):
    """Retourne l'arborescence des catégories touristiques dynamiques pour le tenant actif."""
    result = await db.execute(select(Tenant).where(Tenant.slug == x_tenant_slug))
    tenant = result.scalar_one_or_none()
    if not tenant:
        raise HTTPException(status_code=404, detail="Tenant not found")
    cat_result = await db.execute(
        select(TenantCategory)
        .where(TenantCategory.tenant_id == tenant.id)
        .order_by(TenantCategory.display_order.asc(), TenantCategory.label.asc())
    )
    return cat_result.scalars().all()


@router.post("/categories", response_model=TenantCategoryResponse, status_code=status.HTTP_201_CREATED)
async def create_tenant_category(
    data: TenantCategoryCreate,
    x_tenant_slug: str = Header(default="algeria"),
    db: AsyncSession = Depends(get_db),
    current_admin = Depends(get_current_admin),
):
    """Permet au pipeline IA ou aux administrateurs de créer une catégorie locale."""
    result = await db.execute(select(Tenant).where(Tenant.slug == x_tenant_slug))
    tenant = result.scalar_one_or_none()
    if not tenant:
        raise HTTPException(status_code=404, detail="Tenant not found")

    existing = await db.execute(
        select(TenantCategory).where(
            TenantCategory.tenant_id == tenant.id,
            TenantCategory.slug == data.slug,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Category slug already exists for this destination")

    cat = TenantCategory(tenant_id=tenant.id, **data.model_dump())
    db.add(cat)
    await db.commit()
    await db.refresh(cat)
    return cat


@router.get("/", response_model=List[TenantResponse])
async def list_tenants(
    db: AsyncSession = Depends(get_db),
    current_admin: Tenant = Depends(get_current_admin),
):
    result = await db.execute(select(Tenant).where(Tenant.is_active == True))
    return result.scalars().all()


@router.post("/", response_model=TenantResponse, status_code=status.HTTP_201_CREATED)
async def create_tenant(
    data: TenantCreate,
    db: AsyncSession = Depends(get_db),
    current_admin: Tenant = Depends(get_current_admin),
):
    result = await db.execute(select(Tenant).where(Tenant.slug == data.slug))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Tenant slug already exists")

    tenant = Tenant(**data.model_dump())
    db.add(tenant)
    await db.commit()
    await db.refresh(tenant)
    return tenant


@router.patch("/{tenant_id}", response_model=TenantResponse)
async def update_tenant(
    tenant_id: str,
    data: TenantUpdate,
    db: AsyncSession = Depends(get_db),
    current_admin: Tenant = Depends(get_current_admin),
):
    result = await db.execute(select(Tenant).where(Tenant.id == tenant_id))
    tenant = result.scalar_one_or_none()
    if not tenant:
        raise HTTPException(status_code=404, detail="Tenant not found")

        update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(tenant, field, value)

    await db.commit()
    await db.refresh(tenant)
    return tenant


@router.post(
    "/{tenant_id}/research/run",
    response_model=ResearchJobResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
async def start_tenant_research(
    tenant_id: UUID,
    data: ResearchRunRequest,
    db: AsyncSession = Depends(get_db),
    current_admin: Tenant = Depends(get_current_admin),
):
    """Lance un run de recherche IA pour un tenant (background execution).

    Crée un job en mode ``pending`` puis déclenche le pipeline IA en tâche de
    fond. Le client poll ensuite GET /{tenant_id}/research/jobs/{job_id}.
    """
    result = await db.execute(select(Tenant).where(Tenant.id == tenant_id))
    tenant = result.scalar_one_or_none()
    if not tenant:
        raise HTTPException(status_code=404, detail="Tenant not found")

    # Rate-limit: at most one manual_refresh per rolling cooldown window.
    if data.trigger_type == "manual_refresh":
        cutoff = datetime.now(timezone.utc).replace(
            tzinfo=None,
        ) - timedelta(days=RESEARCH_MANUAL_REFRESH_COOLDOWN_DAYS)
        result = await db.execute(
            select(ResearchJob)
            .where(
                ResearchJob.tenant_id == tenant.id,
                ResearchJob.trigger_type == "manual_refresh",
                ResearchJob.created_at >= cutoff,
            )
            .order_by(ResearchJob.created_at.desc())
        )
        if result.scalar_one_or_none():
            raise HTTPException(
                status_code=429,
                detail="Une actualisation manuelle a déjà été effectuée dans les 30 derniers jours.",
            )

    job = ResearchJob(
        tenant_id=tenant.id,
        trigger_type=data.trigger_type,
        status="pending",
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    # Background task placeholder — the AI research pipeline runs server-side
    # and updates job.status / finished_at / categories_* in place.
    return job


@router.get(
    "/{tenant_id}/research/jobs/{job_id}",
    response_model=ResearchJobResponse,
)
async def get_research_job_status(
    tenant_id: UUID,
    job_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_admin: Tenant = Depends(get_current_admin),
):
    """Retourne le statut d'un job de recherche (polling mobile)."""
    result = await db.execute(
        select(ResearchJob).where(
            ResearchJob.id == job_id,
            ResearchJob.tenant_id == tenant_id,
        )
    )
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Research job not found")
    return job
