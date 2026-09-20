"""Création de tenants : réservée au script d'administration (pas d'endpoint)."""
from typing import Optional, Tuple

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_password_hash
from app.models import Tenant, User
from app.schemas import TenantCreate


class TenantAlreadyExists(Exception):
    """Un tenant avec ce slug existe déjà."""


async def create_tenant_with_admin(
    session: AsyncSession,
    data: TenantCreate,
    admin_email: str,
    admin_password: str,
    admin_full_name: Optional[str] = None,
) -> Tuple[Tenant, User]:
    """Crée un tenant et son premier admin dans une seule transaction.

    Aucun endpoint ne crée de tenant : un tenant sans admin serait
    inadministrable, d'où la création atomique des deux.
    """
    existing = await session.execute(select(Tenant).where(Tenant.slug == data.slug))
    if existing.scalar_one_or_none():
        raise TenantAlreadyExists(data.slug)

    tenant = Tenant(**data.model_dump())
    session.add(tenant)
    await session.flush()

    admin = User(
        tenant_id=tenant.id,
        email=admin_email,
        hashed_password=get_password_hash(admin_password),
        full_name=admin_full_name or "Admin",
        is_active=True,
        is_admin=True,
    )
    session.add(admin)
    await session.commit()
    await session.refresh(tenant)
    await session.refresh(admin)
    return tenant, admin
