"""Review endpoints (POI-scoped).

Reviews belong to a POI, so routes live under /pois/{poi_id}/reviews. Every
create/update/delete that mutates reviews recomputes the parent POI's
average_rating and review_count so the denormalized aggregates never drift.
"""
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Header, status
from sqlalchemy import select, and_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.tenant import get_tenant_from_header
from app.database import get_db
from app.dependencies import get_current_user
from app.models import POI, Review, User
from app.schemas import ReviewCreate, ReviewResponse, ReviewUpdate
from app.services.review_service import recompute_poi_rating

router = APIRouter()


async def _tenant_poi(db: AsyncSession, x_tenant_slug: str, poi_id: str) -> POI:
    tenant = await get_tenant_from_header(x_tenant_slug)
    result = await db.execute(
        select(POI).where(and_(POI.id == poi_id, POI.tenant_id == tenant.id))
    )
    poi = result.scalar_one_or_none()
    if not poi:
        raise HTTPException(status_code=404, detail="POI not found")
    return poi


@router.post(
    "/{poi_id}/reviews",
    response_model=ReviewResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_review(
    poi_id: str,
    data: ReviewCreate,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user: User = Depends(get_current_user),
):
    poi = await _tenant_poi(db, x_tenant_slug, poi_id)

    review = Review(
        tenant_id=poi.tenant_id,
        user_id=current_user.id,
        poi_id=poi.id,
        rating=data.rating,
        comment=data.comment,
    )
    db.add(review)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=409, detail="You have already reviewed this POI"
        )

    await db.refresh(review)
    await recompute_poi_rating(db, poi.id)
    return review


@router.get("/{poi_id}/reviews", response_model=List[ReviewResponse])
async def list_reviews(
    poi_id: str,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user: User = Depends(get_current_user),
):
    poi = await _tenant_poi(db, x_tenant_slug, poi_id)
    result = await db.execute(
        select(Review)
        .where(
            and_(Review.poi_id == poi.id, Review.tenant_id == poi.tenant_id)
        )
        .order_by(Review.created_at.desc())
    )
    return result.scalars().all()


@router.get("/{poi_id}/reviews/{review_id}", response_model=ReviewResponse)
async def get_review(
    poi_id: str,
    review_id: str,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user: User = Depends(get_current_user),
):
    poi = await _tenant_poi(db, x_tenant_slug, poi_id)
    result = await db.execute(
        select(Review).where(
            and_(
                Review.id == review_id,
                Review.poi_id == poi.id,
                Review.tenant_id == poi.tenant_id,
            )
        )
    )
    review = result.scalar_one_or_none()
    if not review:
        raise HTTPException(status_code=404, detail="Review not found")
    return review


@router.patch("/{poi_id}/reviews/{review_id}", response_model=ReviewResponse)
async def update_review(
    poi_id: str,
    review_id: str,
    data: ReviewUpdate,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user: User = Depends(get_current_user),
):
    poi = await _tenant_poi(db, x_tenant_slug, poi_id)
    result = await db.execute(
        select(Review).where(
            and_(
                Review.id == review_id,
                Review.poi_id == poi.id,
                Review.tenant_id == poi.tenant_id,
            )
        )
    )
    review = result.scalar_one_or_none()
    if not review:
        raise HTTPException(status_code=404, detail="Review not found")
    if review.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the author can update this review")

    if data.rating is not None:
        review.rating = data.rating
    if data.comment is not None:
        review.comment = data.comment

    await db.commit()
    await db.refresh(review)
    await recompute_poi_rating(db, poi.id)
    return review


@router.delete("/{poi_id}/reviews/{review_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_review(
    poi_id: str,
    review_id: str,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user: User = Depends(get_current_user),
):
    poi = await _tenant_poi(db, x_tenant_slug, poi_id)
    result = await db.execute(
        select(Review).where(
            and_(
                Review.id == review_id,
                Review.poi_id == poi.id,
                Review.tenant_id == poi.tenant_id,
            )
        )
    )
    review = result.scalar_one_or_none()
    if not review:
        raise HTTPException(status_code=404, detail="Review not found")
    if review.user_id != current_user.id and not current_user.is_admin:
        raise HTTPException(status_code=403, detail="You cannot delete this review")

    await db.delete(review)
    await db.commit()
    await recompute_poi_rating(db, poi.id)
    return None