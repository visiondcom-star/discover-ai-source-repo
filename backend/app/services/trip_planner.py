"""AI-powered trip planning with constraint solving."""
import json
from typing import List, Dict, Any, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from sqlalchemy.orm import selectinload
from app.models import POI, Trip, TripItem, Tenant
from app.schemas import TripGenerateRequest
from app.services.constraint_solver import ConstraintSolver
from app.config import get_settings

settings = get_settings()


class TripPlannerService:
    def __init__(self, db: AsyncSession, tenant: Tenant):
        self.db = db
        self.tenant = tenant
        self.solver = ConstraintSolver()

    async def generate_trip(
        self,
        user_id: str,
        request: TripGenerateRequest,
    ) -> Trip:
        # Fetch candidate POIs for this tenant
        query = select(POI).where(
            and_(
                POI.tenant_id == self.tenant.id,
                POI.is_active == True,
            )
        )

        if request.city:
            query = query.where(POI.city.ilike(f"%{request.city}%"))

        if request.interests:
            # Filter by category matching interests
            categories = [i.lower() for i in request.interests]
            query = query.where(POI.category.in_(categories))

        result = await self.db.execute(query)
        pois = result.scalars().all()

        if not pois:
            # Fallback: get all active POIs
            result = await self.db.execute(
                select(POI).where(
                    and_(POI.tenant_id == self.tenant.id, POI.is_active == True)
                )
            )
            pois = result.scalars().all()

        # Use constraint solver to build itinerary
        itinerary = self.solver.solve(
            pois=list(pois),
            num_days=request.num_days,
            budget_level=request.budget_level,
            travel_style=request.travel_style,
            accessibility_needs=request.accessibility_needs,
            interests=request.interests,
        )

        # Create trip
        trip = Trip(
            tenant_id=self.tenant.id,
            user_id=user_id,
            title=f"Voyage à {request.city or self.tenant.name}",
            description=f"Itinéraire {request.travel_style} de {request.num_days} jours",
            num_days=request.num_days,
            budget_level=request.budget_level,
            budget_currency=request.budget_currency,
            travel_style=request.travel_style,
            interests=request.interests,
            accessibility_needs=request.accessibility_needs,
            dietary_restrictions=request.dietary_restrictions,
            group_type=request.group_type,
            children=request.children,
            status="planned",
        )
        self.db.add(trip)
        await self.db.flush()  # Get trip.id

        # Create trip items
        for day_num, day_pois in enumerate(itinerary, start=1):
            for idx, poi in enumerate(day_pois):
                trip_item = TripItem(
                    trip_id=trip.id,
                    poi_id=poi.id,
                    day_number=day_num,
                    order_index=idx,
                    notes=f"Visite de {poi.name}",
                )
                self.db.add(trip_item)

        await self.db.commit()
        result = await self.db.execute(
            select(Trip)
            .options(selectinload(Trip.items).selectinload(TripItem.poi))
            .where(Trip.id == trip.id)
        )
        return result.scalar_one_or_none()

    async def get_trip_with_items(self, trip_id: str, user_id: str) -> Optional[Trip]:
        result = await self.db.execute(
            select(Trip)
            .options(selectinload(Trip.items).selectinload(TripItem.poi))
            .where(
                and_(
                    Trip.id == trip_id,
                    Trip.user_id == user_id,
                    Trip.tenant_id == self.tenant.id,
                )
            )
        )
        return result.scalar_one_or_none()
