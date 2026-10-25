"""Live context endpoints (weather, events, notifications)."""
from typing import List, Optional
from uuid import UUID
from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, func, update
from datetime import timedelta
from app.database import get_db
from app.models import Notification, Tenant, utcnow
from app.schemas import WeatherResponse, ContextEventCreate
from app.core.tenant import get_tenant_from_header
from app.dependencies import get_current_user
from app.services.notification_service import resolve_locale
from app.services.notification_templates import render_notification
import random

router = APIRouter()

# Mock weather data (replace with real API integration)
WEATHER_MOCK = {
    "Alger": {"temp": 28, "condition": "Ensoleillé", "humidity": 65, "wind": 12},
    "Constantine": {"temp": 26, "condition": "Partiellement nuageux", "humidity": 58, "wind": 15},
    "Tipaza": {"temp": 27, "condition": "Ensoleillé", "humidity": 70, "wind": 10},
    "Oran": {"temp": 25, "condition": "Nuageux", "humidity": 72, "wind": 18},
    "Ghardaia": {"temp": 32, "condition": "Ensoleillé", "humidity": 30, "wind": 8},
    "Djanet": {"temp": 35, "condition": "Ensoleillé", "humidity": 20, "wind": 5},
    "Sétif": {"temp": 22, "condition": "Partiellement nuageux", "humidity": 55, "wind": 14},
}


@router.get("/weather")
async def get_weather(
    city: str = Query(..., min_length=2),
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    # Find closest city match
    city_lower = city.lower()
    weather = None
    for known_city, data in WEATHER_MOCK.items():
        if known_city.lower() in city_lower or city_lower in known_city.lower():
            weather = data
            break

    if not weather:
        weather = {"temp": 25, "condition": "Ensoleillé", "humidity": 60, "wind": 10}

    # Generate 3-day forecast
    forecast = []
    conditions = ["Ensoleillé", "Partiellement nuageux", "Nuageux", "Pluie légère"]
    for i in range(1, 4):
        forecast.append({
            "day": (utcnow() + timedelta(days=i)).strftime("%A"),
            "temp": weather["temp"] + random.randint(-3, 3),
            "condition": random.choice(conditions),
            "humidity": max(20, min(90, weather["humidity"] + random.randint(-10, 10))),
        })

    return WeatherResponse(
        city=city,
        temperature=weather["temp"],
        condition=weather["condition"],
        humidity=weather["humidity"],
        wind_speed=weather["wind"],
        forecast=forecast,
    )


@router.get("/forecast")
async def get_forecast(
    city: str = Query(..., min_length=2),
    days: int = Query(5, ge=1, le=14),
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    conditions = ["Ensoleillé", "Partiellement nuageux", "Nuageux", "Pluie légère", "Orageux"]
    base_temp = 25

    forecast = []
    for i in range(1, days + 1):
        day = utcnow() + timedelta(days=i)
        forecast.append({
            "date": day.strftime("%Y-%m-%d"),
            "day": day.strftime("%A"),
            "temp_max": base_temp + random.randint(0, 5),
            "temp_min": base_temp - random.randint(3, 8),
            "condition": random.choice(conditions),
            "humidity": random.randint(30, 80),
            "wind_speed": random.randint(5, 25),
            "precipitation_chance": random.randint(0, 40),
        })

    return {"city": city, "forecast": forecast}


@router.get("/events")
async def get_events(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
    city: Optional[str] = None,
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    # Mock events
    events = [
        {
            "id": "evt-1",
            "title": "Festival International de Musique Andalouse",
            "city": "Alger",
            "date": "2024-10-15",
            "type": "music",
            "description": "Concert de musique andalouse classique",
        },
        {
            "id": "evt-2",
            "title": "Journées Culturelles de Constantine",
            "city": "Constantine",
            "date": "2024-11-01",
            "type": "culture",
            "description": "Expositions, conférences et spectacles",
        },
        {
            "id": "evt-3",
            "title": "Marathon de Tipaza",
            "city": "Tipaza",
            "date": "2024-09-20",
            "type": "sport",
            "description": "Course le long des ruines romaines",
        },
    ]

    if city:
        events = [e for e in events if city.lower() in e["city"].lower()]

    return {"events": events, "total": len(events)}


@router.post("/events")
async def publish_event(
    data: ContextEventCreate,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    return {
        "id": "evt-new",
        "status": "published",
        "event": data.model_dump(),
        "published_by": str(current_user.id),
    }


@router.get("/notifications")
async def get_notifications(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
    current_user = Depends(get_current_user),
    unread_only: bool = False,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    """Lecture des notifications en base pour l'utilisateur courant du tenant.

    - Filtre par tenant_id et user_id (isolation stricte).
    - Tri par created_at DESC (les plus récentes d'abord).
    - Pagination limit / offset.
    - Format de réponse compatible avec le stub existant : id, title, message, type, read, created_at.
    """
    tenant = await get_tenant_from_header(x_tenant_slug)

    base_conditions = [
        Notification.tenant_id == tenant.id,
        Notification.user_id == current_user.id,
    ]

    # Nombre total non lues
    unread_count_query = select(func.count()).select_from(Notification).where(
        and_(*base_conditions, Notification.read_at.is_(None))
    )
    unread_res = await db.execute(unread_count_query)
    total_unread = unread_res.scalar() or 0

    query_conditions = list(base_conditions)
    if unread_only:
        query_conditions.append(Notification.read_at.is_(None))

    query = (
        select(Notification)
        .where(and_(*query_conditions))
        .order_by(Notification.created_at.desc())
        .offset(offset)
        .limit(limit)
    )
    result = await db.execute(query)
    rows = result.scalars().all()

    # Rendu localisé
    user_loc = resolve_locale(current_user, tenant)
    notifications_data = []
    for notif in rows:
        title, msg = render_notification(
            type_=notif.type,
            locale=notif.locale or user_loc,
            payload=notif.payload,
        )
        notifications_data.append(
            {
                "id": str(notif.id),
                "title": title,
                "message": msg,
                "type": notif.type,
                "read": notif.read_at is not None,
                "created_at": notif.created_at.isoformat() if notif.created_at else None,
                "booking_id": str(notif.booking_id) if notif.booking_id else None,
                "payload": notif.payload,
            }
        )

    return {
        "notifications": notifications_data,
        "unread_count": total_unread,
        "total": len(notifications_data),
        "limit": limit,
        "offset": offset,
    }


@router.post("/notifications/read-all")
async def mark_all_read(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
    current_user = Depends(get_current_user),
):
    """Marque toutes les notifications non lues de l'utilisateur courant comme lues et renvoie le compte réel."""
    tenant = await get_tenant_from_header(x_tenant_slug)
    now = utcnow()

    result = await db.execute(
        update(Notification)
        .where(
            and_(
                Notification.tenant_id == tenant.id,
                Notification.user_id == current_user.id,
                Notification.read_at.is_(None),
            )
        )
        .values(read_at=now)
    )
    await db.commit()
    count = result.rowcount or 0
    return {"marked_as_read": count}


@router.post("/notifications/{notification_id}/read")
async def mark_notification_read(
    notification_id: UUID,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
    current_user = Depends(get_current_user),
):
    """Marque une notification spécifique comme lue."""
    tenant = await get_tenant_from_header(x_tenant_slug)

    res = await db.execute(
        select(Notification).where(
            and_(
                Notification.id == notification_id,
                Notification.tenant_id == tenant.id,
                Notification.user_id == current_user.id,
            )
        )
    )
    notif = res.scalar_one_or_none()
    if not notif:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Notification not found")

    if notif.read_at is None:
        notif.read_at = utcnow()
        await db.commit()
        await db.refresh(notif)

    return {
        "id": str(notif.id),
        "read": True,
        "read_at": notif.read_at.isoformat() if notif.read_at else None,
    }
