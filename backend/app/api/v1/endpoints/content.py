"""Content pipeline endpoints (CSV/JSON import)."""
import csv
import json as json_mod
from io import StringIO
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, Header, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from app.database import get_db
from app.models import POI, Tenant
from app.schemas import ContentImportResponse, POIResponse
from app.core.tenant import get_tenant_from_header
from app.dependencies import get_current_user
from slugify import slugify

router = APIRouter()


@router.post("/import/csv", response_model=ContentImportResponse)
async def import_csv(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    if not file.filename.endswith(".csv"):
        raise HTTPException(status_code=400, detail="File must be a CSV")

    content = await file.read()
    text = content.decode("utf-8")
    reader = csv.DictReader(StringIO(text))

    imported = 0
    errors = 0
    details = []

    for row in reader:
        try:
            slug = slugify(row.get("name", "unknown"))
            # Check for existing slug
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
                name=row.get("name", ""),
                description=row.get("description", ""),
                city=row.get("city", ""),
                category=row.get("category", "culture"),
                duration_minutes=int(row.get("duration_minutes", 60)),
                price_range=row.get("price_range", "free"),
                latitude=float(row.get("latitude", 0)) if row.get("latitude") else None,
                longitude=float(row.get("longitude", 0)) if row.get("longitude") else None,
                address=row.get("address", ""),
                tags=row.get("tags", "").split(",") if row.get("tags") else [],
                is_verified=False,
            )
            db.add(poi)
            imported += 1
            details.append({"name": poi.name, "status": "imported", "slug": slug})
        except Exception as e:
            errors += 1
            details.append({"name": row.get("name", "unknown"), "status": "error", "error": str(e)})

    await db.commit()
    return ContentImportResponse(imported=imported, errors=errors, details=details)


@router.post("/import/json", response_model=ContentImportResponse)
async def import_json(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    if not file.filename.endswith(".json"):
        raise HTTPException(status_code=400, detail="File must be a JSON")

    content = await file.read()
    data = json_mod.loads(content)

    pois_data = data if isinstance(data, list) else data.get("pois", [])

    imported = 0
    errors = 0
    details = []

    for item in pois_data:
        try:
            slug = slugify(item.get("name", "unknown"))
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
                name=item.get("name", ""),
                description=item.get("description", ""),
                city=item.get("city", ""),
                category=item.get("category", "culture"),
                duration_minutes=item.get("duration_minutes", 60),
                price_range=item.get("price_range", "free"),
                latitude=item.get("latitude"),
                longitude=item.get("longitude"),
                address=item.get("address", ""),
                tags=item.get("tags", []),
                is_verified=item.get("is_verified", False),
            )
            db.add(poi)
            imported += 1
            details.append({"name": poi.name, "status": "imported", "slug": slug})
        except Exception as e:
            errors += 1
            details.append({"name": item.get("name", "unknown"), "status": "error", "error": str(e)})

    await db.commit()
    return ContentImportResponse(imported=imported, errors=errors, details=details)


@router.get("/pending")
async def get_pending(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    result = await db.execute(
        select(POI).where(
            and_(POI.tenant_id == tenant.id, POI.is_verified == False, POI.is_active == True)
        )
    )
    pois = result.scalars().all()
    return {"pending": len(pois), "items": [POIResponse.model_validate(p) for p in pois]}


@router.post("/validate")
async def validate_pois(
    poi_ids: list,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    validated = 0
    for poi_id in poi_ids:
        result = await db.execute(
            select(POI).where(and_(POI.id == poi_id, POI.tenant_id == tenant.id))
        )
        poi = result.scalar_one_or_none()
        if poi:
            poi.is_verified = True
            validated += 1
    await db.commit()
    return {"validated": validated}
