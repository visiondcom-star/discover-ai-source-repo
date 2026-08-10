"""Live context endpoints (weather, events, notifications)."""
from typing import List, Optional
from fastapi import APIRouter, Depends, Header, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, func
from datetime import datetime, timedelta
from app.database import get_db
from app.models import Tenant
from app.schemas import WeatherResponse, ContextEventCreate
from app.core.tenant import get_tenant_from_header
from app.dependencies import get_current_user
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
    x_tenant_slug: str = Header(default="algeria"),
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
            "day": (datetime.utcnow() + timedelta(days=i)).strftime("%A"),
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
    x_tenant_slug: str = Header(default="algeria"),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    conditions = ["Ensoleillé", "Partiellement nuageux", "Nuageux", "Pluie légère", "Orageux"]
    base_temp = 25

    forecast = []
    for i in range(1, days + 1):
        forecast.append({
            "date": (datetime.utcnow() + timedelta(days=i)).strftime("%Y-%m-%d"),
            "day": (datetime.utcnow() + timedelta(days=i)).strftime("%A"),
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
    x_tenant_slug: str = Header(default="algeria"),
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
    x_tenant_slug: str = Header(default="algeria"),
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
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
    unread_only: bool = False,
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    notifications = [
        {
            "id": "notif-1",
            "title": "Nouveau POI ajouté",
            "message": "Un nouveau site historique a été ajouté à Alger",
            "type": "poi",
            "read": False,
            "created_at": datetime.utcnow().isoformat(),
        },
        {
            "id": "notif-2",
            "title": "Météo : Vent fort prévu",
            "message": "Des vents forts sont prévus à Constantine demain",
            "type": "weather",
            "read": False,
            "created_at": (datetime.utcnow() - timedelta(hours=2)).isoformat(),
        },
    ]

    if unread_only:
        notifications = [n for n in notifications if not n["read"]]

    return {"notifications": notifications, "unread_count": len([n for n in notifications if not n["read"]])}


@router.post("/notifications/read-all")
async def mark_all_read(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    return {"marked_as_read": 2}
