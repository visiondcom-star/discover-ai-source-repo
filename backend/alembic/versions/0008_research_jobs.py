"""research pipeline: trackable jobs (async run + polling)

Revision ID: 0008_research_jobs
Revises: 0007_research_pipeline
Create Date: 2026-09-17

Adds research_jobs, the missing piece between "a run was requested" and
"here is what happened": one row per POST /tenants/research/run, updated
in place as a FastAPI BackgroundTask progresses it through
pending -> processing -> done|failed. GET /tenants/research/jobs/{id}
polls this row — this is what the mobile ResearchProvider tracks.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0008_research_jobs"
down_revision: Union[str, None] = "0007_research_pipeline"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "research_jobs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("trigger_type", sa.String(20), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("started_at", sa.DateTime(), nullable=True),
        sa.Column("finished_at", sa.DateTime(), nullable=True),
        sa.Column("categories_proposed", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("categories_auto_published", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("categories_pending_review", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_research_jobs_tenant_id", "research_jobs", ["tenant_id"])
    op.create_index("ix_research_jobs_status", "research_jobs", ["status"])
    # Supports the "1x/month manual_refresh" rate-limit check: most recent
    # manual_refresh job for a tenant, without scanning every row.
    op.create_index(
        "ix_research_jobs_tenant_trigger_created",
        "research_jobs",
        ["tenant_id", "trigger_type", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_research_jobs_tenant_trigger_created", table_name="research_jobs")
    op.drop_index("ix_research_jobs_status", table_name="research_jobs")
    op.drop_index("ix_research_jobs_tenant_id", table_name="research_jobs")
    op.drop_table("research_jobs")
