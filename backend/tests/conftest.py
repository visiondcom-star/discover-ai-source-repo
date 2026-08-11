"""Pytest fixtures and configuration."""
import os

import pytest_asyncio
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine, AsyncSession
from sqlalchemy.pool import NullPool

import app.core.tenant as tenant_module
import app.database as database_module
from app.core.security import get_password_hash
from app.database import Base, get_db
from app.main import app
from app.models import POI, Tenant, User

TEST_DATABASE_URL = os.getenv(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://postgres:postgres@localhost:5432/discoverai_test",
)

engine = create_async_engine(TEST_DATABASE_URL, echo=False, future=True, poolclass=NullPool)
TestSessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def override_get_db():
    async with TestSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()


# Route all app DB access to the test database. These are looked up at
# call time, so reassigning the module attributes is sufficient.
database_module.engine = engine
database_module.AsyncSessionLocal = TestSessionLocal
tenant_module.AsyncSessionLocal = TestSessionLocal

app.dependency_overrides[get_db] = override_get_db


async def _seed_algeria_tenant():
    async with TestSessionLocal() as session:
        tenant = Tenant(
            slug="algeria",
            name="Discover Algeria",
            default_language="fr",
            supported_languages=["fr", "ar", "en"],
            default_currency="DZD",
            primary_color="#006233",
            secondary_color="#FFFFFF",
        )
        session.add(tenant)
        await session.commit()


@pytest_asyncio.fixture(scope="session", autouse=True)
async def setup_database():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest_asyncio.fixture(autouse=True)
async def clean_database():
    # Recreate all tables and re-seed the demo tenant before every test so
    # tests never leak rows into each other.
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    await _seed_algeria_tenant()
    yield


@pytest_asyncio.fixture
async def db_session():
    async with TestSessionLocal() as session:
        yield session


@pytest_asyncio.fixture
async def test_tenant(db_session):
    tenant = Tenant(
        slug="test-tenant",
        name="Test Tenant",
        default_language="fr",
        default_currency="DZD",
    )
    db_session.add(tenant)
    await db_session.commit()
    await db_session.refresh(tenant)
    return tenant


@pytest_asyncio.fixture
async def test_user(db_session, test_tenant):
    user = User(
        tenant_id=test_tenant.id,
        email="test@example.com",
        hashed_password=get_password_hash("testpass123"),
        full_name="Test User",
        is_active=True,
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


@pytest_asyncio.fixture
async def test_admin(db_session, test_tenant):
    user = User(
        tenant_id=test_tenant.id,
        email="admin@example.com",
        hashed_password=get_password_hash("adminpass123"),
        full_name="Admin User",
        is_active=True,
        is_admin=True,
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


@pytest_asyncio.fixture
async def client():
    async with AsyncClient(app=app, base_url="http://test") as ac:
        yield ac


@pytest_asyncio.fixture
async def auth_headers(client, test_user, test_tenant):
    response = await client.post(
        "/api/v1/auth/login",
        headers={"X-Tenant-Slug": "test-tenant"},
        json={"email": "test@example.com", "password": "testpass123"},
    )
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}", "X-Tenant-Slug": "test-tenant"}


@pytest_asyncio.fixture
async def admin_headers(client, test_admin, test_tenant):
    response = await client.post(
        "/api/v1/auth/login",
        headers={"X-Tenant-Slug": "test-tenant"},
        json={"email": "admin@example.com", "password": "adminpass123"},
    )
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}", "X-Tenant-Slug": "test-tenant"}
