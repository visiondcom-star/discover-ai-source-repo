"""Tenant resolution and middleware."""
from fastapi import Request, HTTPException, Header
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models import Tenant
from app.database import AsyncSessionLocal


async def get_tenant_from_header(x_tenant_slug: str = Header(default="algeria")) -> Tenant:
    async with AsyncSessionLocal() as session:
        result = await session.execute(
            select(Tenant).where(Tenant.slug == x_tenant_slug, Tenant.is_active == True)
        )
        tenant = result.scalar_one_or_none()
        if not tenant:
            raise HTTPException(status_code=404, detail=f"Tenant '{x_tenant_slug}' not found")
        return tenant


async def get_current_tenant(request: Request) -> Tenant:
    tenant_slug = request.headers.get("x-tenant-slug", "algeria")
    return await get_tenant_from_header(tenant_slug)
