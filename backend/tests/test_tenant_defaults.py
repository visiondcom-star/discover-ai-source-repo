"""Tests for Tenant model defaults."""
import pytest

from app.models import Tenant

pytestmark = pytest.mark.asyncio


async def test_tenant_default_primary_color(db_session):
    tenant = Tenant(
        slug="test-defaults",
        name="Test Defaults",
        default_language="fr",
        default_currency="EUR",
    )
    db_session.add(tenant)
    await db_session.flush()

    assert tenant.primary_color == "#0F4C3A"
