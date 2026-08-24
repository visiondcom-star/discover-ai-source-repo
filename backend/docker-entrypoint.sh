#!/bin/sh
set -e

echo "[entrypoint] ENV=${ENV:-development} — applying Alembic migrations before serving traffic..."

# Reuses the application's own migration logic (including baseline stamping
# of legacy databases created by the old create_all bootstrap).
# Importing app.main also instantiates Settings, so the production config
# guard (insecure SECRET_KEY) fails the container here, before uvicorn starts.
python -c "from app.main import _run_migrations as _run_migrations; _run_migrations()"

echo "[entrypoint] migrations up to date — starting: $*"
exec "$@"