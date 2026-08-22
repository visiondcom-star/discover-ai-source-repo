"""CV tests — /cv/identify via the LLM-provider vision path (deterministic mock)."""
import pytest

TEST_IMAGE = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9"


@pytest.mark.asyncio
async def test_identify_requires_auth(client, test_tenant):
    response = await client.post(
        "/api/v1/cv/identify",
        headers={"X-Tenant-Slug": "test-tenant"},
        files={"file": ("image.jpg", TEST_IMAGE, "image/jpeg")},
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_identify_returns_identification(client, auth_headers, test_tenant):
    response = await client.post(
        "/api/v1/cv/identify",
        headers=auth_headers,
        files={"file": ("image.jpg", TEST_IMAGE, "image/jpeg")},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["image_processed"] is True
    assert data["tenant"] == "test-tenant"
    identification = data["identification"]
    assert "label" in identification
    assert "confidence" in identification
    assert "description" in identification
    assert "possible_pois" in identification
    assert isinstance(identification["possible_pois"], list)


@pytest.mark.asyncio
async def test_identify_is_deterministic(client, auth_headers, test_tenant):
    # Same image bytes must always map to the same (mock) identification.
    first = await client.post(
        "/api/v1/cv/identify",
        headers=auth_headers,
        files={"file": ("image.jpg", TEST_IMAGE, "image/jpeg")},
    )
    second = await client.post(
        "/api/v1/cv/identify",
        headers=auth_headers,
        files={"file": ("image.jpg", TEST_IMAGE, "image/jpeg")},
    )
    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["identification"]["label"] == second.json()["identification"]["label"]