"""Booking agent endpoints with consent flow."""
import hashlib
import json
from datetime import timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Header, Response, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from app.constants import BOOKING_CONFIRM_SLA_HOURS, BOOKING_MODES_SUPPORTED
from app.database import get_db
from app.models import Booking, POI, Tenant, utcnow
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


def _request_hash(data: BookingCreate) -> str:
    """Empreinte stable de la requête : détecte une clé d'idempotence réutilisée
    avec un corps différent. L'ordre des clés JSON n'a pas d'influence."""
    canonical = json.dumps(
        {
            "poi_id": str(data.poi_id),
            "adapter_type": data.adapter_type,
            "booking_data": data.booking_data,
        },
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


async def _find_by_key(db: AsyncSession, tenant_id, user_id, key: str) -> Optional[Booking]:
    result = await db.execute(
        select(Booking).where(
            and_(
                Booking.tenant_id == tenant_id,
                Booking.user_id == user_id,
                Booking.idempotency_key == key,
            )
        )
    )
    return result.scalar_one_or_none()


def _replay_or_conflict(existing: Booking, request_hash: str, response: Response) -> Booking:
    """Même clé : même requête → on renvoie la réservation existante (200) ;
    requête différente → 409. Jamais de doublon, jamais de silence."""
    if existing.request_hash != request_hash:
        raise HTTPException(
            status_code=409,
            detail="Idempotency-Key already used with a different request",
        )
    response.status_code = status.HTTP_200_OK
    return existing


@router.post("/", response_model=BookingResponse, status_code=status.HTTP_201_CREATED)
async def create_booking(
    data: BookingCreate,
    response: Response,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
    current_user=Depends(get_current_user),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key", min_length=8, max_length=80),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    # Capturés en scalaire AVANT toute écriture : le rollback du chemin course
    # expire les objets de cette session (dont current_user, chargé via get_db),
    # et relire un attribut expiré lancerait un refresh synchrone (MissingGreenlet).
    tenant_id = tenant.id
    user_id = current_user.id
    request_hash = _request_hash(data)

    # 1) Rejeu : une clé déjà vue ne recrée jamais de réservation.
    if idempotency_key:
        existing = await _find_by_key(db, tenant_id, user_id, idempotency_key)
        if existing:
            return _replay_or_conflict(existing, request_hash, response)

    # 2) Le POI doit exister dans ce tenant.
    result = await db.execute(
        select(POI).where(and_(POI.id == data.poi_id, POI.tenant_id == tenant.id))
    )
    poi = result.scalar_one_or_none()
    if not poi:
        raise HTTPException(status_code=404, detail="POI not found")

    if data.adapter_type not in ADAPTERS:
        raise HTTPException(status_code=400, detail="Invalid adapter type")

    # 3) Le mode du POI décide si la réservation est possible.
    mode = poi.booking_mode or "request"
    if mode == "info_only":
        raise HTTPException(status_code=422, detail="This place is information only and cannot be booked")
    if mode not in BOOKING_MODES_SUPPORTED:
        raise HTTPException(status_code=422, detail=f"Booking mode '{mode}' is not supported yet")

    booking = Booking(
        tenant_id=tenant_id,
        user_id=user_id,
        poi_id=data.poi_id,
        adapter_type=data.adapter_type,
        status="pending",
        consent_given=False,
        currency=tenant.default_currency,  # derive from tenant, never a hardcoded literal
        booking_data=data.booking_data,
        booking_mode=mode,  # figé : un changement ultérieur du POI n'affecte pas cette réservation
        respond_by=(utcnow() + timedelta(hours=BOOKING_CONFIRM_SLA_HOURS)) if mode == "manual_confirm" else None,
        idempotency_key=idempotency_key,
        request_hash=request_hash if idempotency_key else None,
    )
    db.add(booking)
    try:
        await db.commit()
    except IntegrityError:
        # Course : deux requêtes simultanées avec la même clé. La contrainte unique a
        # départagé ; on relit la gagnante et on rejoue la logique de rejeu.
        await db.rollback()
        if not idempotency_key:
            raise
        existing = await _find_by_key(db, tenant_id, user_id, idempotency_key)
        if not existing:
            raise
        return _replay_or_conflict(existing, request_hash, response)

    await db.refresh(booking)
    return booking


@router.get("/", response_model=List[BookingResponse])
async def list_bookings(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
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
    x_tenant_slug: str = Header(...),
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
    x_tenant_slug: str = Header(...),
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
        booking.consent_timestamp = utcnow()
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
    x_tenant_slug: str = Header(...),
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
    x_tenant_slug: str = Header(...),
    current_user = Depends(get_current_user),
):
    return {"adapters": ADAPTERS}
