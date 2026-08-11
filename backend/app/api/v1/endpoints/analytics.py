"""Analytics and dashboard endpoints."""
from typing import List, Optional, Dict, Any
from fastapi import APIRouter, Depends, Header, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, func
from datetime import datetime, timedelta
from app.database import get_db
from app.models import AnalyticsEvent, User, POI, Trip, Booking, Tenant
from app.schemas import AnalyticsTrackRequest, DashboardOverview
from app.core.tenant import get_tenant_from_header
from app.dependencies import get_current_user

router = APIRouter()


@router.post("/track")
async def track_event(
    data: AnalyticsTrackRequest,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    event = AnalyticsEvent(
        tenant_id=tenant.id,
        user_id=current_user.id,
        event_type=data.event_type,
        event_data=data.event_data,
        session_id=data.session_id,
    )
    db.add(event)
    await db.commit()
    return {"status": "tracked", "event_id": str(event.id)}


@router.post("/track/batch")
async def track_batch(
    events: List[AnalyticsTrackRequest],
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    tracked = 0
    for evt in events:
        event = AnalyticsEvent(
            tenant_id=tenant.id,
            user_id=current_user.id,
            event_type=evt.event_type,
            event_data=evt.event_data,
            session_id=evt.session_id,
        )
        db.add(event)
        tracked += 1
    await db.commit()
    return {"status": "tracked", "count": tracked}


@router.get("/dashboard/overview", response_model=DashboardOverview)
async def dashboard_overview(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    # Count queries
    total_users = await db.execute(
        select(func.count(User.id)).where(User.tenant_id == tenant.id)
    )
    total_pois = await db.execute(
        select(func.count(POI.id)).where(and_(POI.tenant_id == tenant.id, POI.is_active == True))
    )
    total_trips = await db.execute(
        select(func.count(Trip.id)).where(Trip.tenant_id == tenant.id)
    )
    total_bookings = await db.execute(
        select(func.count(Booking.id)).where(Booking.tenant_id == tenant.id)
    )

    today = datetime.utcnow().date()
    active_today = await db.execute(
        select(func.count(AnalyticsEvent.id)).where(
            and_(
                AnalyticsEvent.tenant_id == tenant.id,
                func.date(AnalyticsEvent.created_at) == today,
            )
        )
    )
    events_today = active_today.scalar()

    return DashboardOverview(
        total_users=total_users.scalar(),
        total_pois=total_pois.scalar(),
        total_trips=total_trips.scalar(),
        total_bookings=total_bookings.scalar(),
        active_users_today=events_today,
        events_today=events_today,
    )


@router.get("/dashboard/content")
async def content_analytics(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    result = await db.execute(
        select(POI.category, func.count(POI.id))
        .where(and_(POI.tenant_id == tenant.id, POI.is_active == True))
        .group_by(POI.category)
    )
    categories = {cat: count for cat, count in result.all()}

    return {
        "categories": categories,
        "top_cities": ["Alger", "Constantine", "Tipaza"],
        "pending_validation": 0,
    }


@router.get("/dashboard/users")
async def user_analytics(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    # New users per day (last 7 days)
    days = []
    for i in range(6, -1, -1):
        day = datetime.utcnow().date() - timedelta(days=i)
        count_result = await db.execute(
            select(func.count(User.id)).where(
                and_(
                    User.tenant_id == tenant.id,
                    func.date(User.created_at) == day,
                )
            )
        )
        days.append({"date": day.isoformat(), "new_users": count_result.scalar()})

    return {
        "new_users_per_day": days,
        "total_active": 0,
        "top_interests": ["culture", "nature", "historical"],
    }


@router.get("/export/{export_type}")
async def export_data(
    export_type: str,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    if export_type == "pois":
        result = await db.execute(
            select(POI).where(and_(POI.tenant_id == tenant.id, POI.is_active == True))
        )
        pois = result.scalars().all()

        import csv
        from io import StringIO
        output = StringIO()
        writer = csv.writer(output)
        writer.writerow(["id", "name", "city", "category", "duration_minutes", "price_range"])
        for p in pois:
            writer.writerow([str(p.id), p.name, p.city, p.category, p.duration_minutes, p.price_range])

        return {
            "type": "csv",
            "filename": f"{tenant.slug}_pois_export.csv",
            "data": output.getvalue(),
        }

    return {"type": export_type, "data": "Export not implemented for this type"}
