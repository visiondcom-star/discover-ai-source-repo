"""Booking agent endpoints with consent flow."""
from typing import List
from fastapi import APIRouter, Depends, HTTPException, Header, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from datetime import datetime
from app.database import get_db
from app.models import Booking, POI, Tenant
from app.schemas import BookingCreate, BookingResponse, ConsentRequest
from app.core.tenant import get_tenant_from_header
from app.dependencies import get_current_user

router = APIRouter()

# Available booking adapters
ADAPTERS = {
    "hotel": {"name": "HotelBookingAdapter", "status": "active"},
    "restaurant": {"name": "RestaurantAdapter", "status": "active"},
    "tour": {"name": "TourGuideAdapter", "status": "beta"},
    "transport": {"name": "TransportAdapter", "status": "active"},
}


@router.post("/", response_model=BookingResponse, status_code=status.HTTP_201_CREATED)
async def create_booking(
    data: BookingCreate,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    # Verify POI exists
    result = await db.execute(
        select(POI).where(and_(POI.id == data.poi_id, POI.tenant_id == tenant.id))
    )
    poi = result.scalar_one_or_none()
    if not poi:
        raise HTTPException(status_code=404, detail="POI not found")

    if data.adapter_type not in ADAPTERS:
        raise HTTPException(status_code=400, detail="Invalid adapter type")

    booking = Booking(
        tenant_id=tenant.id,
        user_id=current_user.id,
        poi_id=data.poi_id,
        adapter_type=data.adapter_type,
        status="pending",
        consent_given=False,
        booking_data=data.booking_data,
    )
    db.add(booking)
    await db.commit()
    await db.refresh(booking)
    return booking


@router.get("/", response_model=List[BookingResponse])
async def list_bookings(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
    status_filter: str = None,
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    query = select(Booking).where(
        and_(Booking.user_id == current_user.id, Booking.tenant_id == tenant.id)
    )
    if status_filter:
        query = query.where(Booking.status == status_filter)
    query = query.order_by(Booking.created_at.desc())

    result = await db.execute(query)
    return result.scalars().all()


@router.get("/{booking_id}", response_model=BookingResponse)
async def get_booking(
    booking_id: str,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    result = await db.execute(
        select(Booking).where(
            and_(
                Booking.id == booking_id,
                Booking.user_id == current_user.id,
                Booking.tenant_id == tenant.id,
            )
        )
    )
    booking = result.scalar_one_or_none()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")
    return booking


@router.post("/{booking_id}/consent")
async def give_consent(
    booking_id: str,
    data: ConsentRequest,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    result = await db.execute(
        select(Booking).where(
            and_(
                Booking.id == booking_id,
                Booking.user_id == current_user.id,
                Booking.tenant_id == tenant.id,
            )
        )
    )
    booking = result.scalar_one_or_none()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")

    if data.consent:
        booking.consent_given = True
        booking.consent_timestamp = datetime.utcnow()
        booking.status = "confirmed"
        # Here you would call the actual adapter
        booking.external_id = f"EXT-{booking_id[:8]}"
    else:
        booking.status = "cancelled"

    await db.commit()
    await db.refresh(booking)
    return booking


@router.post("/{booking_id}/cancel")
async def cancel_booking(
    booking_id: str,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    result = await db.execute(
        select(Booking).where(
            and_(
                Booking.id == booking_id,
                Booking.user_id == current_user.id,
                Booking.tenant_id == tenant.id,
            )
        )
    )
    booking = result.scalar_one_or_none()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")

    if booking.status == "confirmed" and booking.consent_given:
        # Would trigger adapter cancellation here
        pass

    booking.status = "cancelled"
    await db.commit()
    await db.refresh(booking)
    return booking


@router.get("/adapters/available")
async def list_adapters(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    return {"adapters": ADAPTERS}
