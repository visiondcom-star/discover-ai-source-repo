"""Tenant management endpoints."""
from typing import List
import hashlib
from datetime import datetime, timezone, timedelta
from uuid import UUID
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Header, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db, AsyncSessionLocal
from app.models import Tenant, TenantCategory, ResearchJob, DestinationResearchDocument
from app.schemas import (
    TenantCreate,
    TenantUpdate,
    TenantResponse,
    TenantCategoryCreate,
    TenantCategoryResponse,
    ResearchJobResponse,
    ResearchRunRequest,
    ResearchDocumentIngest,
    ResearchDocumentResponse,
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
    "/{tenant_id}/research/documents",
    response_model=ResearchDocumentResponse,
)
async def ingest_research_document(
    tenant_id: UUID,
    data: ResearchDocumentIngest,
    db: AsyncSession = Depends(get_db),
    current_admin: Tenant = Depends(get_current_admin),
):
    """Ingère un document brut de recherche destination (étape Ingestion).

    Idempotent par (tenant_id, content_hash) : redéposer le même texte ne
    crée pas de doublon, renvoie simplement le document déjà stocké.
    """
    result = await db.execute(select(Tenant).where(Tenant.id == tenant_id))
    tenant = result.scalar_one_or_none()
    if not tenant:
        raise HTTPException(status_code=404, detail="Tenant not found")

    content_hash = hashlib.sha256(data.raw_text.strip().encode("utf-8")).hexdigest()

    existing = await db.execute(
        select(DestinationResearchDocument).where(
            DestinationResearchDocument.tenant_id == tenant.id,
            DestinationResearchDocument.content_hash == content_hash,
        )
    )
    existing_doc = existing.scalar_one_or_none()
    if existing_doc:
        return existing_doc

    doc = DestinationResearchDocument(
        tenant_id=tenant.id,
        source_type=data.source_type,
        source_url=data.source_url,
        raw_text=data.raw_text,
        language=data.language,
        content_hash=content_hash,
    )
    db.add(doc)
    await db.commit()
    await db.refresh(doc)
    return doc


async def _run_research_pipeline(job_id):
    """Exécute le pipeline en tâche de fond (sa propre session DB).

    STUB : fait avancer le job pending -> processing -> done sans
    extraction réelle pour l'instant.
    """
    async with AsyncSessionLocal() as session:
        result = await session.execute(
            select(ResearchJob).where(ResearchJob.id == job_id)
        )
        job = result.scalar_one_or_none()
        if not job:
            return

        job.status = "processing"
        job.started_at = datetime.now(timezone.utc).replace(tzinfo=None)
        await session.commit()

        try:
            job.categories_proposed = 0
            job.categories_auto_published = 0
            job.categories_pending_review = 0
            job.status = "done"
        except Exception as exc:
            job.status = "failed"
            job.error_message = str(exc)
        finally:
            job.finished_at = datetime.now(timezone.utc).replace(tzinfo=None)
            await session.commit()


@router.post(
    "/{tenant_id}/research/run",
    response_model=ResearchJobResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
async def start_tenant_research(
    tenant_id: UUID,
    data: ResearchRunRequest,
    background_tasks: BackgroundTasks,
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
                detail="Une actualisation manuelle a déjà été effectuée ce mois-ci.",
            )

    job = ResearchJob(
        tenant_id=tenant.id,
        trigger_type=data.trigger_type,
        status="pending",
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    background_tasks.add_task(_run_research_pipeline, job.id)
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
