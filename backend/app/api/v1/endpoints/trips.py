"""Trip planning endpoints."""
from typing import List
from fastapi import APIRouter, Depends, HTTPException, Header, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from app.database import get_db
from app.models import Trip, User
from app.schemas import TripGenerateRequest, TripResponse
from app.core.tenant import get_tenant_from_header
from app.dependencies import get_current_user
from app.services.trip_planner import TripPlannerService

router = APIRouter()


@router.post("/generate", response_model=TripResponse, status_code=status.HTTP_201_CREATED)
async def generate_trip(
    data: TripGenerateRequest,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user: User = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    # Budget currency defaults to the tenant's configured currency — never a
    # hardcoded literal. The schema must stay tenant-agnostic (it cannot know
    # the current tenant), so the fallback is resolved here, at the endpoint.
    if data.budget_currency is None:
        data.budget_currency = tenant.default_currency
    planner = TripPlannerService(db, tenant)
    trip = await planner.generate_trip(str(current_user.id), data)
    return trip


@router.get("/", response_model=List[TripResponse])
async def list_trips(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user: User = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    result = await db.execute(
        select(Trip).where(
            and_(Trip.user_id == current_user.id, Trip.tenant_id == tenant.id)
        ).order_by(Trip.created_at.desc())
    )
    return result.scalars().all()


@router.get("/{trip_id}", response_model=TripResponse)
async def get_trip(
    trip_id: str,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user: User = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    planner = TripPlannerService(db, tenant)
    trip = await planner.get_trip_with_items(trip_id, str(current_user.id))
    if not trip:
        raise HTTPException(status_code=404, detail="Trip not found")
    return trip
