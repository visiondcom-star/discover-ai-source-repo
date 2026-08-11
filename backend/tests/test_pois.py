"""POI tests — 7 tests."""
import pytest


@pytest.mark.asyncio
async def test_list_pois_no_auth(client, test_tenant):
    response = await client.get(
        "/api/v1/pois/",
        headers={"X-Tenant-Slug": "test-tenant"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "items" in data
    assert "total" in data


@pytest.mark.asyncio
async def test_list_pois_with_filters(client, test_tenant, auth_headers, db_session):
    from app.models import POI
    poi = POI(
        tenant_id=test_tenant.id,
        slug="test-poi",
        name="Test POI",
        city="Alger",
        category="historical",
        duration_minutes=60,
        is_active=True,
    )
    db_session.add(poi)
    await db_session.commit()

    response = await client.get(
        "/api/v1/pois/?city=Alger&category=historical",
        headers={"X-Tenant-Slug": "test-tenant"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 1


@pytest.mark.asyncio
async def test_search_pois(client, test_tenant, auth_headers, db_session):
    from app.models import POI
    poi = POI(
        tenant_id=test_tenant.id,
        slug="search-poi",
        name="Searchable POI",
        city="Oran",
        category="culture",
        duration_minutes=90,
        is_active=True,
    )
    db_session.add(poi)
    await db_session.commit()

    response = await client.get(
        "/api/v1/pois/?search=Searchable",
        headers={"X-Tenant-Slug": "test-tenant"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 1


@pytest.mark.asyncio
async def test_create_poi(client, auth_headers, test_tenant):
    response = await client.post(
        "/api/v1/pois/",
        headers=auth_headers,
        json={
            "name": "New POI",
            "city": "Constantine",
            "category": "culture",
            "duration_minutes": 120,
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "New POI"
    assert data["slug"] == "new-poi"


@pytest.mark.asyncio
async def test_create_poi_requires_auth(client, test_tenant):
    response = await client.post(
        "/api/v1/pois/",
        headers={"X-Tenant-Slug": "test-tenant"},
        json={"name": "Unauthorized POI", "city": "Alger", "category": "nature"},
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_poi_tenant_isolation(client, auth_headers, db_session, test_tenant):
    from app.models import POI
    # Create POI in test-tenant
    poi = POI(
        tenant_id=test_tenant.id,
        slug="isolated-poi",
        name="Isolated POI",
        city="Alger",
        category="historical",
        is_active=True,
    )
    db_session.add(poi)
    await db_session.commit()

    # Should not appear in algeria tenant
    response = await client.get(
        "/api/v1/pois/",
        headers={"X-Tenant-Slug": "algeria"},
    )
    assert response.status_code == 200
    data = response.json()
    # The demo data might exist, but our test POI should not be there
    slugs = [p["slug"] for p in data["items"]]
    assert "isolated-poi" not in slugs


@pytest.mark.asyncio
async def test_delete_poi(client, auth_headers, db_session, test_tenant):
    from app.models import POI
    poi = POI(
        tenant_id=test_tenant.id,
        slug="delete-me",
        name="Delete Me",
        city="Alger",
        category="nature",
        is_active=True,
    )
    db_session.add(poi)
    await db_session.commit()
    await db_session.refresh(poi)

    response = await client.delete(
        f"/api/v1/pois/{poi.id}",
        headers=auth_headers,
    )
    assert response.status_code == 204
