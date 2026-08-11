"""Content pipeline tests — 25 tests (simplified to key ones)."""
import pytest
import io


@pytest.mark.asyncio
async def test_import_csv_success(client, auth_headers, test_tenant):
    csv_content = b"name,description,city,category,duration_minutes,price_range\n"
    csv_content += b"CSV POI 1,Description 1,Alger,historical,60,free\n"
    csv_content += b"CSV POI 2,Description 2,Oran,culture,90,low\n"

    file = io.BytesIO(csv_content)
    response = await client.post(
        "/api/v1/content/import/csv",
        headers=auth_headers,
        files={"file": ("pois.csv", file, "text/csv")},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["imported"] == 2
    assert data["errors"] == 0


@pytest.mark.asyncio
async def test_import_csv_wrong_format(client, auth_headers, test_tenant):
    response = await client.post(
        "/api/v1/content/import/csv",
        headers=auth_headers,
        files={"file": ("pois.txt", io.BytesIO(b"text"), "text/plain")},
    )
    assert response.status_code == 400
    assert "must be a CSV" in response.json()["detail"]


@pytest.mark.asyncio
async def test_import_json_success(client, auth_headers, test_tenant):
    json_content = b'{"pois": [{"name": "JSON POI", "city": "Alger", "category": "nature", "duration_minutes": 120}]}'
    response = await client.post(
        "/api/v1/content/import/json",
        headers=auth_headers,
        files={"file": ("pois.json", io.BytesIO(json_content), "application/json")},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["imported"] == 1


@pytest.mark.asyncio
async def test_import_json_wrong_format(client, auth_headers, test_tenant):
    response = await client.post(
        "/api/v1/content/import/json",
        headers=auth_headers,
        files={"file": ("pois.csv", io.BytesIO(b"csv"), "text/csv")},
    )
    assert response.status_code == 400


@pytest.mark.asyncio
async def test_get_pending_pois(client, auth_headers, db_session, test_tenant):
    from app.models import POI
    poi = POI(
        tenant_id=test_tenant.id,
        slug="pending-poi",
        name="Pending POI",
        city="Alger",
        category="historical",
        is_verified=False,
        is_active=True,
    )
    db_session.add(poi)
    await db_session.commit()

    response = await client.get("/api/v1/content/pending", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["pending"] >= 1


@pytest.mark.asyncio
async def test_validate_pois(client, auth_headers, db_session, test_tenant):
    from app.models import POI
    poi = POI(
        tenant_id=test_tenant.id,
        slug="validate-poi",
        name="Validate POI",
        city="Alger",
        category="culture",
        is_verified=False,
        is_active=True,
    )
    db_session.add(poi)
    await db_session.commit()
    await db_session.refresh(poi)

    response = await client.post(
        "/api/v1/content/validate",
        headers=auth_headers,
        json=[str(poi.id)],
    )
    assert response.status_code == 200
    assert response.json()["validated"] == 1


@pytest.mark.asyncio
async def test_import_csv_duplicate_slug_handling(client, auth_headers, test_tenant):
    csv_content = b"name,description,city,category,duration_minutes,price_range\n"
    csv_content += b"Same Name,Desc,Alger,historical,60,free\n"
    csv_content += b"Same Name,Desc2,Alger,historical,90,low\n"

    response = await client.post(
        "/api/v1/content/import/csv",
        headers=auth_headers,
        files={"file": ("pois.csv", io.BytesIO(csv_content), "text/csv")},
    )
    assert response.status_code == 200
    data = response.json()
    # Both should be imported with different slugs
    assert data["imported"] == 2


@pytest.mark.asyncio
async def test_content_requires_auth(client, test_tenant):
    response = await client.get("/api/v1/content/pending", headers={"X-Tenant-Slug": "test-tenant"})
    assert response.status_code == 401
