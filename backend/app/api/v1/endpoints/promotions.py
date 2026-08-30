"""Home-screen promo banner endpoints."""
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Header, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_, func
from app.database import get_db
from app.models import Promotion, User
from app.schemas import PromotionCreate, PromotionUpdate, PromotionResponse, PromotionListResponse
from app.core.tenant import get_tenant_from_header
from app.dependencies import get_current_user
from app.models import utcnow

router = APIRouter()


# Both "/promotions" and "/promotions/" are registered for the same reason
# as pois.py: FastAPI's redirect_slashes would 307-redirect with an
# ABSOLUTE Location built from the proxied Host, which breaks behind the
# Next.js rewrite and for browsers talking to the frontend same-origin.
@router.get("/", response_model=PromotionListResponse)
@router.get("", response_model=PromotionListResponse, include_in_schema=False)
async def list_promotions(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
):
    """Public: active promotions for the current tenant, in display order.

    Filters out anything outside its starts_at/ends_at scheduling window so
    the client never has to reason about dates — if it's returned, it's
    showable right now.
    """
    tenant = await get_tenant_from_header(x_tenant_slug)
    now = utcnow()

    query = (
        select(Promotion)
        .where(
            and_(
                Promotion.tenant_id == tenant.id,
                Promotion.is_active == True,
                or_(Promotion.starts_at == None, Promotion.starts_at <= now),
                or_(Promotion.ends_at == None, Promotion.ends_at >= now),
            )
        )
        .order_by(Promotion.priority.desc(), Promotion.created_at.desc())
    )
    count_query = select(func.count(Promotion.id)).where(
        and_(
            Promotion.tenant_id == tenant.id,
            Promotion.is_active == True,
            or_(Promotion.starts_at == None, Promotion.starts_at <= now),
            or_(Promotion.ends_at == None, Promotion.ends_at >= now),
        )
    )

    result = await db.execute(query)
    promotions = result.scalars().all()
    total = (await db.execute(count_query)).scalar_one()

    return PromotionListResponse(items=list(promotions), total=total)


@router.post("/", response_model=PromotionResponse, status_code=status.HTTP_201_CREATED)
async def create_promotion(
    data: PromotionCreate,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user: User = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    promotion = Promotion(
        tenant_id=tenant.id,
        **data.model_dump(),
    )
    db.add(promotion)
    await db.commit()
    await db.refresh(promotion)
    return promotion


@router.patch("/{promotion_id}", response_model=PromotionResponse)
async def update_promotion(
    promotion_id: str,
    data: PromotionUpdate,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user: User = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    result = await db.execute(
        select(Promotion).where(
            and_(Promotion.id == promotion_id, Promotion.tenant_id == tenant.id)
        )
    )
    promotion = result.scalar_one_or_none()
    if not promotion:
        raise HTTPException(status_code=404, detail="Promotion not found")

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(promotion, field, value)

    await db.commit()
    await db.refresh(promotion)
    return promotion


@router.delete("/{promotion_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_promotion(
    promotion_id: str,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user: User = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    result = await db.execute(
        select(Promotion).where(
            and_(Promotion.id == promotion_id, Promotion.tenant_id == tenant.id)
        )
    )
    promotion = result.scalar_one_or_none()
    if not promotion:
        raise HTTPException(status_code=404, detail="Promotion not found")

    promotion.is_active = False
    await db.commit()
    return None
