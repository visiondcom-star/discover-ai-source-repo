"""User tests — verify the unique email-per-tenant database constraint."""
import pytest
from sqlalchemy.exc import IntegrityError

from app.core.security import get_password_hash
from app.models import Tenant, User


@pytest.mark.asyncio
async def test_user_email_must_be_unique_within_tenant(
    db_session, test_tenant
):
    """A duplicate email inside the same tenant must violate the constraint."""
    hashed = get_password_hash("password123")

    first = User(
        tenant_id=test_tenant.id,
        email="alice@example.com",
        hashed_password=hashed,
        full_name="Alice",
    )
    db_session.add(first)
    await db_session.commit()
    await db_session.refresh(first)

    second = User(
        tenant_id=test_tenant.id,
        email="alice@example.com",  # same email, same tenant -> violation
        hashed_password=hashed,
        full_name="Alice Duplicate",
    )
    db_session.add(second)
    with pytest.raises(IntegrityError):
        await db_session.commit()
    await db_session.rollback()


@pytest.mark.asyncio
async def test_user_email_can_repeat_across_tenants(
    db_session, test_tenant
):
    """The same email is allowed in a different tenant (constraint is per-tenant)."""
    hashed = get_password_hash("password123")

    first = User(
        tenant_id=test_tenant.id,
        email="bob@example.com",
        hashed_password=hashed,
        full_name="Bob",
    )
    db_session.add(first)
    await db_session.commit()
    await db_session.refresh(first)

    other_tenant = Tenant(
        slug="other-tenant-uniq",
        name="Other Tenant",
        default_language="fr",
        default_currency="DZD",
    )
    db_session.add(other_tenant)
    await db_session.commit()
    await db_session.refresh(other_tenant)

    second = User(
        tenant_id=other_tenant.id,
        email="bob@example.com",  # same email, different tenant -> allowed
        hashed_password=hashed,
        full_name="Bob Other Tenant",
    )
    db_session.add(second)
    await db_session.commit()  # must not raise
    await db_session.refresh(second)
    assert second.id is not None
