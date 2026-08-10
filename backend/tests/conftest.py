"""Pytest fixtures and configuration."""
import pytest_asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from httpx import AsyncClient
from app.main import app
from app.database import get_db, Base
from app.models import Tenant, User, POI
from app.core.security import get_password_hash

TEST_DATABASE_URL = "postgresql+asyncpg://postgres:postgres@localhost:5432/discoverai_test"

engine = create_async_engine(TEST_DATABASE_URL, echo=False, future=True)
TestSessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def override_get_db():
    async with TestSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()


app.dependency_overrides[get_db] = override_get_db


@pytest_asyncio.fixture(scope="session", autouse=True)
async def setup_database():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


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
