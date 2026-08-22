"""Review tests — POI rating aggregates stay in sync on create/update/delete."""
import pytest


async def _create_poi(client, db_session, test_tenant, slug="review-poi"):
    from app.models import POI

    poi = POI(
        tenant_id=test_tenant.id,
        slug=slug,
        name="Review POI",
        city="Alger",
        category="historical",
        is_active=True,
    )
    db_session.add(poi)
    await db_session.commit()
    await db_session.refresh(poi)
    return poi


async def _create_review(client, auth_headers, poi_id, rating, comment=None):
    payload = {"rating": rating}
    if comment is not None:
        payload["comment"] = comment
    return await client.post(
        f"/api/v1/pois/{poi_id}/reviews",
        headers=auth_headers,
        json=payload,
    )


async def _poi_aggregates(db_session, poi):
    # The POI instance lives in db_session's identity map (expire_on_commit=False),
    # so a re-select would return the stale in-memory object. Refresh reloads the
    # committed values written by the recompute step in the API layer.
    await db_session.refresh(poi)
    return poi.review_count, poi.average_rating


@pytest.mark.asyncio
async def test_create_review_updates_aggregates(client, auth_headers, db_session, test_tenant):
    from app.models import POI

    poi = await _create_poi(client, db_session, test_tenant, slug="agg-poi")

    response = await _create_review(client, auth_headers, poi.id, 5, "Excellent")
    assert response.status_code == 201
    data = response.json()
    assert data["rating"] == 5
    assert data["comment"] == "Excellent"

    count, average = await _poi_aggregates(db_session, poi)
    assert count == 1
    assert average == 5.0


@pytest.mark.asyncio
async def test_multi_review_average(client, auth_headers, admin_headers, db_session, test_tenant):
    from app.models import POI

    poi = await _create_poi(client, db_session, test_tenant, slug="avg-poi")

    r1 = await _create_review(client, auth_headers, poi.id, 4)
    assert r1.status_code == 201
    r2 = await _create_review(client, admin_headers, poi.id, 2)
    assert r2.status_code == 201

    count, average = await _poi_aggregates(db_session, poi)
    assert count == 2
    assert average == 3.0


@pytest.mark.asyncio
async def test_duplicate_review_rejected(client, auth_headers, db_session, test_tenant):
    from app.models import POI

    poi = await _create_poi(client, db_session, test_tenant, slug="dup-poi")

    r1 = await _create_review(client, auth_headers, poi.id, 5)
    assert r1.status_code == 201

    r2 = await _create_review(client, auth_headers, poi.id, 4)
    assert r2.status_code == 409

    count, average = await _poi_aggregates(db_session, poi)
    assert count == 1
    assert average == 5.0


@pytest.mark.asyncio
async def test_update_review_recomputes(client, auth_headers, db_session, test_tenant):
    from app.models import POI

    poi = await _create_poi(client, db_session, test_tenant, slug="update-poi")

    r1 = await _create_review(client, auth_headers, poi.id, 5)
    assert r1.status_code == 201
    review_id = r1.json()["id"]

    response = await client.patch(
        f"/api/v1/pois/{poi.id}/reviews/{review_id}",
        headers=auth_headers,
        json={"rating": 1},
    )
    assert response.status_code == 200
    assert response.json()["rating"] == 1

    count, average = await _poi_aggregates(db_session, poi)
    assert count == 1
    assert average == 1.0


@pytest.mark.asyncio
async def test_delete_review_recomputes(client, auth_headers, admin_headers, db_session, test_tenant):
    from app.models import POI

    poi = await _create_poi(client, db_session, test_tenant, slug="del-poi")

    r1 = await _create_review(client, auth_headers, poi.id, 4)
    assert r1.status_code == 201
    r2 = await _create_review(client, admin_headers, poi.id, 2)
    assert r2.status_code == 201

    review_id = r1.json()["id"]
    response = await client.delete(
        f"/api/v1/pois/{poi.id}/reviews/{review_id}",
        headers=auth_headers,
    )
    assert response.status_code == 204

    count, average = await _poi_aggregates(db_session, poi)
    assert count == 1
    assert average == 2.0


@pytest.mark.asyncio
async def test_reviews_tenant_isolation(client, auth_headers, db_session, test_tenant):
    from app.models import POI

    poi = await _create_poi(client, db_session, test_tenant, slug="iso-poi")

    # Reusing a 'test-tenant' token against the 'algeria' tenant is rejected by
    # auth (tenant mismatch 403) before the endpoint even looks up the POI.
    response = await client.post(
        f"/api/v1/pois/{poi.id}/reviews",
        headers={"Authorization": auth_headers["Authorization"], "X-Tenant-Slug": "algeria"},
        json={"rating": 5},
    )
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_review_requires_auth(client, db_session, test_tenant):
    from app.models import POI

    poi = await _create_poi(client, db_session, test_tenant, slug="auth-poi")

    response = await client.post(
        f"/api/v1/pois/{poi.id}/reviews",
        headers={"X-Tenant-Slug": "test-tenant"},
        json={"rating": 5},
    )
    assert response.status_code == 401