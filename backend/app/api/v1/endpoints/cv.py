"""Computer Vision & AR endpoints."""
from typing import List, Optional
from fastapi import APIRouter, Depends, UploadFile, File, Header, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, func
from app.database import get_db
from app.models import POI, Tenant
from app.core.tenant import get_tenant_from_header
from app.dependencies import get_current_user
import random

router = APIRouter()


@router.post("/identify")
async def identify_object(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    # Mock CV identification (would use GPT-4V or custom model)
    possible_identifications = [
        {
            "label": "Monument historique",
            "confidence": 0.92,
            "description": "Cela ressemble à un monument historique de style mauresque.",
            "possible_pois": ["Casbah d'Alger", "Palais des Rais"],
        },
        {
            "label": "Site naturel",
            "confidence": 0.85,
            "description": "Paysage désertique avec formations rocheuses.",
            "possible_pois": ["Tassili n'Ajjer", "Hoggar"],
        },
        {
            "label": "Pont historique",
            "confidence": 0.88,
            "description": "Pont suspendu en pierre, architecture ottomane.",
            "possible_pois": ["Ponts de Constantine"],
        },
    ]

    identification = random.choice(possible_identifications)

    return {
        "identification": identification,
        "image_processed": True,
        "tenant": tenant.slug,
    }


@router.get("/ar/poi/{poi_id}")
async def get_ar_assets(
    poi_id: str,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    result = await db.execute(
        select(POI).where(and_(POI.id == poi_id, POI.tenant_id == tenant.id))
    )
    poi = result.scalar_one_or_none()
    if not poi:
        return {"error": "POI not found"}

    # Mock AR assets
    ar_assets = {
        "poi_id": poi_id,
        "name": poi.name,
        "ar_overlay": {
            "type": "historical_reconstruction",
            "model_url": f"/ar/models/{poi.slug}.glb",
            "scale": 1.0,
            "position": {"x": 0, "y": 0, "z": 0},
        },
        "info_points": [
            {"title": "Histoire", "content": poi.description or "Description non disponible", "position": {"x": 1, "y": 2, "z": 0}},
            {"title": "Architecture", "content": "Style architectural local", "position": {"x": -1, "y": 1.5, "z": 0}},
        ],
        "available": True,
    }

    return ar_assets


@router.get("/ar/nearby")
async def get_nearby_ar(
    lat: float = Query(...),
    lon: float = Query(...),
    radius: float = Query(1000, ge=100, le=10000),
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    # Get nearby POIs (simplified - no PostGIS for mock)
    result = await db.execute(
        select(POI).where(
            and_(
                POI.tenant_id == tenant.id,
                POI.is_active == True,
                POI.latitude != None,
                POI.longitude != None,
            )
        )
    )
    pois = result.scalars().all()

    # Simple distance filter (would use PostGIS in production)
    nearby = []
    for poi in pois:
        if poi.latitude and poi.longitude:
            dist = ((poi.latitude - lat)**2 + (poi.longitude - lon)**2)**0.5 * 111000  # rough meters
            if dist <= radius:
                nearby.append({
                    "poi_id": str(poi.id),
                    "name": poi.name,
                    "distance_meters": int(dist),
                    "ar_available": True,
                    "category": poi.category,
                })

    nearby.sort(key=lambda x: x["distance_meters"])
    return {"pois": nearby[:10], "total": len(nearby)}
