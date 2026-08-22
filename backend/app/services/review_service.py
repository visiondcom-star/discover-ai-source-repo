"""Keep POI rating aggregates in sync with the reviews table.

POI.average_rating and POI.review_count are denormalized aggregate columns;
this module provides the single place that recomputes them from the Review
rows so callers (endpoints, seeds, scripts) never drift out of sync.
"""
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import POI, Review


async def recompute_poi_rating(db: AsyncSession, poi_id) -> None:
    """Recompute average_rating and review_count for a given POI.

    If the POI has no reviews, review_count is set to 0 and average_rating
    to None (matching the column's nullable definition). Results are rounded
    to 2 decimals. Commits the change.
    """
    agg = await db.execute(
        select(func.count(Review.id), func.avg(Review.rating)).where(
            Review.poi_id == poi_id
        )
    )
    review_count, average = agg.first()

    result = await db.execute(select(POI).where(POI.id == poi_id))
    poi = result.scalar_one_or_none()
    if poi is None:
        return

    poi.review_count = int(review_count or 0)
    poi.average_rating = round(float(average), 2) if average is not None else None
    await db.commit()