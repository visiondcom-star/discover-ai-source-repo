"""Constraint solver for trip itinerary optimization."""
from typing import List, Dict, Any, Optional, TypeVar, TYPE_CHECKING
from dataclasses import dataclass
import random

if TYPE_CHECKING:
    from app.models import POI

T = TypeVar("T")


@dataclass
class POIProxy:
    id: str
    name: str
    city: str
    category: str
    duration_minutes: int
    price_range: str
    latitude: float
    longitude: float
    tags: List[str]
    accessibility: List[str]


class ConstraintSolver:
    """Solves trip planning constraints using greedy + local search."""

    PRICE_MAP = {"free": 0, "low": 1, "medium": 2, "high": 3}
    MAX_DAILY_MINUTES = {"relaxed": 240, "balanced": 420, "intensive": 600}
    MAX_DAILY_POIS = {"relaxed": 3, "balanced": 5, "intensive": 7}

    def solve(
        self,
        pois: List[T],
        num_days: int,
        budget_level: str,
        travel_style: str,
        accessibility_needs: List[str],
        interests: List[str],
    ) -> List[List[T]]:
        """Returns list of days, each day is a list of POIs."""

        # Convert to proxies
        poi_proxies = []
        for p in pois:
            poi_proxies.append(POIProxy(
                id=str(p.id),
                name=p.name,
                city=p.city,
                category=p.category,
                duration_minutes=p.duration_minutes,
                price_range=p.price_range,
                latitude=p.latitude or 0.0,
                longitude=p.longitude or 0.0,
                tags=p.tags or [],
                accessibility=p.accessibility or [],
            ))

        # Filter by accessibility
        if accessibility_needs:
            poi_proxies = [
                p for p in poi_proxies
                if all(need in p.accessibility for need in accessibility_needs)
            ]

        # Score and sort POIs
        scored = []
        for p in poi_proxies:
            score = self._score_poi(p, interests, budget_level)
            scored.append((score, p))

        scored.sort(reverse=True, key=lambda x: x[0])
        sorted_pois = [p for _, p in scored]

        # Greedy assignment to days
        days = [[] for _ in range(num_days)]
        day_minutes = [0] * num_days

        max_daily = self.MAX_DAILY_MINUTES.get(travel_style, 420)
        max_pois = self.MAX_DAILY_POIS.get(travel_style, 5)

        for poi in sorted_pois:
            # Find best day (least filled that can fit this POI)
            best_day = -1
            best_fill = float('inf')

            for d in range(num_days):
                if (day_minutes[d] + poi.duration_minutes <= max_daily and
                    len(days[d]) < max_pois):
                    if day_minutes[d] < best_fill:
                        best_fill = day_minutes[d]
                        best_day = d

            if best_day >= 0:
                days[best_day].append(poi)
                day_minutes[best_day] += poi.duration_minutes

        # Convert proxies back to original objects
        id_to_poi = {str(p.id): p for p in pois}
        result = []
        for day in days:
            day_pois = [id_to_poi[p.id] for p in day if p.id in id_to_poi]
            if day_pois:
                result.append(day_pois)

        return result

    def _score_poi(self, poi: POIProxy, interests: List[str], budget_level: str) -> float:
        score = 0.0

        # Interest match
        if interests:
            for interest in interests:
                if interest.lower() in poi.category.lower():
                    score += 10
                if any(interest.lower() in tag.lower() for tag in poi.tags):
                    score += 5

        # Budget alignment
        target_price = self.PRICE_MAP.get(budget_level, 2)
        poi_price = self.PRICE_MAP.get(poi.price_range, 2)
        score += 5 - abs(target_price - poi_price)

        # Prefer moderate duration (not too short, not too long)
        if 60 <= poi.duration_minutes <= 180:
            score += 3

        # Diversity bonus (handled at day level, but slight randomization helps)
        score += random.uniform(0, 1)

        return score

    def calculate_distance(self, lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """Haversine distance in km."""
        import math
        R = 6371
        dlat = math.radians(lat2 - lat1)
        dlon = math.radians(lon2 - lon1)
        a = (math.sin(dlat/2)**2 +
             math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon/2)**2)
        return R * 2 * math.asin(math.sqrt(a))
