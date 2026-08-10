"""Points of Interest endpoints."""
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, Header, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_, func
from app.database import get_db
from app.models import POI, Tenant, User
from app.schemas import POICreate, POIUpdate, POIResponse, POIListResponse
from app.core.tenant import get_tenant_from_header
from app.dependencies import get_current_user
from slugify import slugify

router = APIRouter()


@router.get("/", response_model=POIListResponse)
async def list_pois(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    city: Optional[str] = Query(None),
    category: Optional[str] = Query(None),
    tag: Optional[str] = Query(None),
    search: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    query = select(POI).where(and_(POI.tenant_id == tenant.id, POI.is_active == True))
    count_query = select(func.count(POI.id)).where(and_(POI.tenant_id == tenant.id, POI.is_active == True))

    if city:
        query = query.where(POI.city.ilike(f"%{city}%"))
        count_query = count_query.where(POI.city.ilike(f"%{city}%"))

    if category:
        query = query.where(POI.category == category)
        count_query = count_query.where(POI.category == category)

    if tag:
        query = query.where(POI.tags.any(tag))
        count_query = count_query.where(POI.tags.any(tag))

    if search:
        search_filter = or_(
            POI.name.ilike(f"%{search}%"),
            POI.description.ilike(f"%{search}%"),
            POI.city.ilike(f"%{search}%"),
        )
        query = query.where(search_filter)
        count_query = count_query.where(search_filter)

    # Pagination
    offset = (page - 1) * page_size
    query = query.offset(offset).limit(page_size)

    result = await db.execute(query)
    pois = result.scalars().all()

    total_result = await db.execute(count_query)
    total = total_result.scalar()

    return POIListResponse(
        items=[POIResponse.model_validate(p) for p in pois],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.get("/{poi_id}", response_model=POIResponse)
async def get_poi(
    poi_id: str,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    result = await db.execute(
        select(POI).where(and_(POI.id == poi_id, POI.tenant_id == tenant.id))
    )
    poi = result.scalar_one_or_none()
    if not poi:
        raise HTTPException(status_code=404, detail="POI not found")
    return poi


@router.post("/", response_model=POIResponse, status_code=status.HTTP_201_CREATED)
async def create_poi(
    data: POICreate,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user: User = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    slug = slugify(data.name)
    # Ensure unique slug per tenant
    base_slug = slug
    counter = 1
    while True:
        result = await db.execute(
            select(POI).where(and_(POI.slug == slug, POI.tenant_id == tenant.id))
        )
        if not result.scalar_one_or_none():
            break
        slug = f"{base_slug}-{counter}"
        counter += 1

    poi = POI(
        tenant_id=tenant.id,
        slug=slug,
        **data.model_dump(),
    )
    db.add(poi)
    await db.commit()
    await db.refresh(poi)
    return poi


@router.patch("/{poi_id}", response_model=POIResponse)
async def update_poi(
    poi_id: str,
    data: POIUpdate,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user: User = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    result = await db.execute(
        select(POI).where(and_(POI.id == poi_id, POI.tenant_id == tenant.id))
    )
    poi = result.scalar_one_or_none()
    if not poi:
        raise HTTPException(status_code=404, detail="POI not found")

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(poi, field, value)

    await db.commit()
    await db.refresh(poi)
    return poi


@router.delete("/{poi_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_poi(
    poi_id: str,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user: User = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    result = await db.execute(
        select(POI).where(and_(POI.id == poi_id, POI.tenant_id == tenant.id))
    )
    poi = result.scalar_one_or_none()
    if not poi:
        raise HTTPException(status_code=404, detail="POI not found")

    poi.is_active = False
    await db.commit()
    return None
