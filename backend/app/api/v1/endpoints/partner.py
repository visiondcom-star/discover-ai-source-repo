"""Endpoints partenaire : réponse aux réservations `manual_confirm`.

Monté sous `/partner`. Un « partenaire » est un utilisateur du tenant rattaché à
au moins un POI via `poi_managers` ; un admin du tenant peut aussi répondre
(secours). Aucun accès cross-tenant : chaque requête filtre par `tenant_id` +
appartenance du POI. Hors périmètre => 404 (jamais 403, pour ne pas révéler
l'existence d'une réservation).

Dépend de la présence (issue de 0012) de `booking_mode` et `respond_by` sur
`Booking`, et de `get_partner_poi_ids` dans `app.dependencies`.
"""
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Header, Query, Response, status
from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.tenant import get_tenant_from_header
from app.database import get_db
from app.dependencies import get_current_user, get_partner_poi_ids
from app.models import POI, Booking, POIManager, User, utcnow
from app.schemas import (
    PartnerRespond,
    PartnerBookingResponse,
    POIManagerCreate,
    POIManagerResponse,
    BookingResponse,
)
from app.services.booking_lifecycle import expire_overdue_requests

router = APIRouter()

# Décision -> état résultant. Rejouer la même décision est idempotent ;
# une décision contraire renvoie 409.
_RESULT_OF = {"confirm": "confirmed", "decline": "declined"}

# Seules ces clés de `booking_data` sont exposées dans
# `PartnerBookingResponse.details` (liste blanche : défense en profondeur).
# Le prestataire voit ce qu'il lui faut pour décider (date, nombre de
# personnes, remarques) ; toute autre clé (phone_number, contact_email, ...)
# est écartée, même si un client l'a écrite dans `booking_data`. Voir
# `test_partner_sees_needed_details_but_never_pii`.
_DETAILS_ALLOWED_KEYS = frozenset(
    {
        "date",
        "start_date",
        "end_date",
        "time",
        "nights",
        "guests",
        "party_size",
        "adults",
        "children",
        "duration",
        "notes",
        "message",
        "special_requests",
    }
)


def _safe_details(booking_data: Optional[dict]) -> dict:
    """Liste blanche : seules les clés utiles à la décision sont exposées.

    Toute clé inconnue (phone_number, contact_email, ...) est écartée.
    """
    return {
        k: v
        for k, v in (dict(booking_data or {})).items()
        if str(k).lower() in _DETAILS_ALLOWED_KEYS
    }


def _scope_filter(tenant_id: UUID, poi_ids: Optional[set], current_user: User):
    """Filtre de portée : le tenant + (admin ? tout : POI gérés).

    Un ensemble de POI vide ne matchera aucune ligne (=> 404 naturel).
    """
    if current_user.is_admin:
        return Booking.tenant_id == tenant_id
    return and_(
        Booking.tenant_id == tenant_id,
        Booking.poi_id.in_(poi_ids or set()),
    )


def _require_partner(current_user: User, poi_ids: Optional[set]) -> None:
    """403 si l'utilisateur n'est ni admin ni rattaché à un POI du tenant.

    C'est l'accès à la FONCTION qui est refusé (403), pas une ressource précise.
    """
    if current_user.is_admin or poi_ids:
        return
    raise HTTPException(status_code=403, detail="Partner access required")


def _require_admin(current_user: User) -> None:
    if not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")


async def _require_poi_in_tenant(db: AsyncSession, tenant_id, poi_id: str) -> None:
    """Le POI existe-t-il dans ce tenant ? Sinon 404 (isolation stricte)."""
    result = await db.execute(
        select(POI).where(and_(POI.id == poi_id, POI.tenant_id == tenant_id))
    )
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="POI not found")


async def _to_partner_response(db: AsyncSession, booking: Booking) -> PartnerBookingResponse:
    """Construit la réponse partenaire.

    Confidentialité : on n'expose que le NOM du voyageur (jamais l'email, jamais
    le mot de passe). Les détails de la réservation (`details`) sont en revanche
    nécessaires au partenaire pour DÉCIDER (date, nombre de personnes,
    remarques) : le champ est peuplé avec `booking_data` UNIQUEMENT ici (route
    partenaire/admin), et il ne doit contenir aucune donnée sensible — jamais
    d'email, de téléphone ni de pièce d'identité saisis par l'app. Voir §3.3 et
    `test_partner_sees_needed_details_but_never_pii`.

    On part du `model_dump()` du BookingResponse puis on ÉCRASE les clés
    (`.update`) plutôt que de les repasser en argument : BookingResponse expose
    déjà `partner_note`/`responded_at` (§3.1), donc `PartnerBookingResponse(
    **base, partner_note=…, responded_at=…)` lèverait
    « multiple values for keyword argument ».
    """
    poi_result = await db.execute(select(POI.name).where(POI.id == booking.poi_id))
    poi_name = poi_result.scalar_one_or_none() or ""

    traveller_result = await db.execute(
        select(User.full_name).where(User.id == booking.user_id)
    )
    traveller_name = traveller_result.scalar_one_or_none()

    base = BookingResponse.model_validate(booking).model_dump()
    base.update(
        poi_name=poi_name,
        traveller_name=traveller_name,
        partner_note=booking.partner_note,
        responded_at=booking.responded_at,
        # Détails utiles à la décision, réservés à la route partenaire/admin.
        details=_safe_details(booking.booking_data),
    )
    return PartnerBookingResponse(**base)


# ---- Liste & réponse ---------------------------------------------------------

@router.get("/bookings", response_model=List[PartnerBookingResponse])
async def list_partner_bookings(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
    current_user: User = Depends(get_current_user),
    poi_ids: set = Depends(get_partner_poi_ids),
    status_filter: str = Query("requested"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    """Demandes à traiter pour les POI gérés (défaut : `requested`).

    Tri : échéance la plus proche d'abord (NULLS LAST), puis création.
    """
    tenant = await get_tenant_from_header(x_tenant_slug)
    _require_partner(current_user, poi_ids)

    # Expire d'abord les demandes en retard pour que la file reflète l'état réel.
    # Scalaires capturés AVANT : expire_overdue_requests committe, et tout
    # attribut ORM relu ensuite sur cette session async lèverait MissingGreenlet
    # (cf. même remarque dans create_booking, 0012).
    tenant_id = tenant.id
    await expire_overdue_requests(db, tenant_id)

    query = (
        select(Booking)
        .where(_scope_filter(tenant_id, poi_ids, current_user))
        .where(Booking.status == status_filter)
        .order_by(Booking.respond_by.asc().nullslast(), Booking.created_at.asc())
        .limit(limit)
        .offset(offset)
    )
    result = await db.execute(query)
    bookings = result.scalars().all()
    return [await _to_partner_response(db, b) for b in bookings]


@router.get("/bookings/{booking_id}", response_model=PartnerBookingResponse)
async def get_partner_booking(
    booking_id: str,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
    current_user: User = Depends(get_current_user),
    poi_ids: set = Depends(get_partner_poi_ids),
):
    """Détail d'une réservation du périmètre (lecture, hors périmètre => 404).

    Sert notamment à consulter `details` (date, personnes, remarques) avant de
    décider. Le scope est le même que la liste : hors du périmètre ou introuvable,
    c'est 404 — jamais 403, pour ne pas révéler l'existence d'une réservation.
    """
    tenant = await get_tenant_from_header(x_tenant_slug)
    _require_partner(current_user, poi_ids)
    await expire_overdue_requests(db, tenant.id)

    result = await db.execute(
        select(Booking).where(
            and_(Booking.id == booking_id, _scope_filter(tenant.id, poi_ids, current_user))
        )
    )
    booking = result.scalar_one_or_none()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")
    return await _to_partner_response(db, booking)


@router.post("/bookings/{booking_id}/respond", response_model=PartnerBookingResponse)
async def respond_to_booking(
    booking_id: str,
    data: PartnerRespond,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
    current_user: User = Depends(get_current_user),
    poi_ids: set = Depends(get_partner_poi_ids),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    _require_partner(current_user, poi_ids)

    # Identifiants en scalaires AVANT toute écriture : `expire_overdue_requests`
    # fait un commit interne qui, selon le réglage `expire_on_commit` de la
    # session, peut expirer les objets ORM (dont current_user). Capturer tôt la
    # clé rend le endpoint indépendant de ce réglage : on ne relit jamais un
    # attribut ORM après ce commit (=> pas de rechargement lazy async, donc pas
    # de MissingGreenlet). §4.2.
    partner_id = current_user.id

    await expire_overdue_requests(db, tenant.id)

    # Verrou de ligne : deux réponses concurrentes sont sérialisées par la base.
    result = await db.execute(
        select(Booking)
        .where(
            and_(
                Booking.id == booking_id,
                _scope_filter(tenant.id, poi_ids, current_user),
            )
        )
        .with_for_update()
    )
    booking = result.scalar_one_or_none()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")

    current_status = booking.status
    resulting = _RESULT_OF[data.decision]

    if current_status == "requested":
        if data.decision == "confirm":
            booking.status = "confirmed"
            # Même format d'identifiant externe que le flux historique.
            booking.external_id = f"EXT-{str(booking.id)[:8]}"
            # consent_timestamp conservé : le voyageur a déjà consenti.
        else:
            booking.status = "declined"
        booking.responded_by = partner_id
        booking.responded_at = utcnow()
        booking.partner_note = data.note
    elif current_status == resulting and booking.responded_by is not None:
        # Rejeu de la MÊME décision déjà prise par un prestataire : idempotent,
        # rien à changer (200). Le garde-fou `responded_by is not None` évite
        # qu'un statut « déjà au bon endroit » mais jamais tranché par un
        # prestataire (ex. `request` passé `confirmed` par le voyageur) ne
        # renvoie un 200 trompeur : un partenaire qui répond « confirm » sur une
        # réservation qu'il n'a pas lui-même confirmée doit tomber dans le 409
        # ci-dessous (§3.2).
        pass
    else:
        # Tout autre état (décision contraire, expired, cancelled...) => 409.
        raise HTTPException(status_code=409, detail="Booking is not awaiting a response")

    await db.commit()
    await db.refresh(booking)
    return await _to_partner_response(db, booking)



# ---- Rattachements (admin) ---------------------------------------------------

@router.get("/pois/{poi_id}/managers", response_model=List[POIManagerResponse])
async def list_managers(
    poi_id: str,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
    current_user: User = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    _require_admin(current_user)
    await _require_poi_in_tenant(db, tenant.id, poi_id)

    result = await db.execute(
        select(POIManager).where(
            and_(POIManager.tenant_id == tenant.id, POIManager.poi_id == poi_id)
        )
    )
    return result.scalars().all()


@router.post(
    "/pois/{poi_id}/managers",
    response_model=POIManagerResponse,
    status_code=status.HTTP_201_CREATED,
    # `responses` documente le doublon idempotent (200, voir JSONResponse
    # ci-dessous) : la doc OpenAPI affiche sinon uniquement le statut du
    # décorateur.
    responses={200: {"description": "Rattachement déjà existant (idempotent)"}},
)
async def add_manager(
    poi_id: str,
    data: POIManagerCreate,
    response: Response,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
    current_user: User = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    _require_admin(current_user)
    await _require_poi_in_tenant(db, tenant.id, poi_id)

    # L'utilisateur rattaché doit appartenir au même tenant, sinon 404.
    user_result = await db.execute(
        select(User).where(and_(User.id == data.user_id, User.tenant_id == tenant.id))
    )
    if not user_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="User not found")

    # Idempotent : un rattachement déjà présent est renvoyé tel quel (200).
    existing = await db.execute(
        select(POIManager).where(
            and_(
                POIManager.tenant_id == tenant.id,
                POIManager.poi_id == poi_id,
                POIManager.user_id == data.user_id,
            )
        )
    )
    dup = existing.scalar_one_or_none()
    if dup:
        response.status_code = status.HTTP_200_OK
        return dup

    manager = POIManager(tenant_id=tenant.id, poi_id=poi_id, user_id=data.user_id)
    db.add(manager)
    await db.commit()
    await db.refresh(manager)
    return manager


@router.delete(
    "/pois/{poi_id}/managers/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def remove_manager(
    poi_id: str,
    user_id: str,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
    current_user: User = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    _require_admin(current_user)
    await _require_poi_in_tenant(db, tenant.id, poi_id)

    result = await db.execute(
        select(POIManager).where(
            and_(
                POIManager.tenant_id == tenant.id,
                POIManager.poi_id == poi_id,
                POIManager.user_id == user_id,
            )
        )
    )
    manager = result.scalar_one_or_none()
    if not manager:
        raise HTTPException(status_code=404, detail="Manager not found")

    await db.delete(manager)
    await db.commit()
    return None

