"""Chat tests — 3 tests."""
import pytest


@pytest.mark.asyncio
async def test_chat_basic(client, auth_headers):
    response = await client.post(
        "/api/v1/chat/",
        headers=auth_headers,
        json={"message": "Bonjour, quels sont les meilleurs sites à Alger ?"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "message" in data
    assert "suggestions" in data


@pytest.mark.asyncio
async def test_chat_with_context(client, auth_headers):
    response = await client.post(
        "/api/v1/chat/",
        headers=auth_headers,
        json={
            "message": "Je veux visiter la Casbah",
            "context": {"city": "Alger", "interests": ["historical"]},
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert len(data["message"]) > 10


@pytest.mark.asyncio
async def test_chat_requires_auth(client, test_tenant):
    response = await client.post(
        "/api/v1/chat/",
        headers={"X-Tenant-Slug": "test-tenant"},
        json={"message": "Test"},
    )
    assert response.status_code == 401
