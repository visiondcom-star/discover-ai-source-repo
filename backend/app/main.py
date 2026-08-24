"""FastAPI application entry point."""
import asyncio
from contextlib import asynccontextmanager
from pathlib import Path

from alembic import command
from alembic.config import Config
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from prometheus_client import make_asgi_app

from app.config import get_settings
from app.api.v1.api import api_router
from app.database import engine, Base
from app.initial_data import init_db

settings = get_settings()

ALEMBIC_INI = Path(__file__).resolve().parent.parent / "alembic.ini"


def _run_migrations() -> None:
    """Apply pending Alembic migrations (runs in a worker thread: the async
    env.py spins up its own event loop via asyncio.run).

    Handles adoption of legacy databases whose schema was created by the old
    ``Base.metadata.create_all`` bootstrap: they have tables but no
    ``alembic_version`` row. Instead of crashing on "table already exists",
    we stamp the baseline revision and continue upgrading from there.
    """
    alembic_cfg = Config(str(ALEMBIC_INI))
    if asyncio.run(_has_unversioned_schema()):
        command.stamp(alembic_cfg, "0001_initial")
    command.upgrade(alembic_cfg, "head")


async def _has_unversioned_schema() -> bool:
    """True when the target DB already has app tables but no alembic_version."""
    from sqlalchemy import inspect
    from sqlalchemy.ext.asyncio import create_async_engine

    engine = create_async_engine(settings.DATABASE_URL)
    try:
        async with engine.connect() as conn:
            def _check(sync_conn) -> bool:
                table_names = inspect(sync_conn).get_table_names()
                return bool(table_names) and "alembic_version" not in table_names

            return await conn.run_sync(_check)
    finally:
        await engine.dispose()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup — schema is owned by Alembic (no more create_all), then seed demo data.
    await asyncio.to_thread(_run_migrations)
    await init_db()
    yield
    # Shutdown
    await engine.dispose()


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.VERSION,
    description="AI Destination OS — Multi-Tenant International Travel Platform",
    lifespan=lifespan,
)

# CORS — origins come from CORS_ORIGINS (comma-separated). In production the
# settings guard refuses to boot when it is unset or contains "*".
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Prometheus metrics
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

# API routes
app.include_router(api_router, prefix="/api/v1")


@app.get("/health")
async def health_check():
    return {"status": "healthy", "version": settings.VERSION, "tenant_ready": True}


@app.get("/")
async def root():
    return {
        "name": settings.APP_NAME,
        "version": settings.VERSION,
        "docs": "/docs",
        "health": "/health",
    }


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error", "error": str(exc)},
    )
