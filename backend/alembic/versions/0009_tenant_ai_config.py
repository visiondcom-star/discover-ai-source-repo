"""tenant AI config and BYOK credentials

Revision ID: 0009_tenant_ai_config
Revises: 0008_research_jobs
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0009_tenant_ai_config"
down_revision = "0008_research_jobs"  # vérifier : doit égaler `revision` de 0008_research_jobs.py
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "tenant_ai_configs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "tenant_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("tenants.id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("primary_provider", sa.String(32), nullable=False, server_default="openai"),
        sa.Column("fallback_provider", sa.String(32), nullable=True),
        sa.Column("models", sa.JSON(), nullable=False, server_default=sa.text("'{}'")),
        sa.Column("default_params", sa.JSON(), nullable=False, server_default=sa.text("'{}'")),
        sa.Column(
            "enabled_features",
            postgresql.ARRAY(sa.String()),
            nullable=False,
            server_default=sa.text("'{chat,recommendation}'"),
        ),
        sa.Column("monthly_spend_limit_usd", sa.Numeric(10, 4), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    op.create_table(
        "tenant_ai_credentials",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "tenant_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("tenants.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("provider", sa.String(32), nullable=False),
        sa.Column("encrypted_key", sa.Text(), nullable=False),
        sa.Column("key_version", sa.Integer(), nullable=False),
        sa.Column("key_last4", sa.String(4), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("rotated_at", sa.DateTime(), nullable=True),
        sa.UniqueConstraint("tenant_id", "provider", name="uq_tenant_ai_credential"),
    )
    # Sert aux rotations de clé maître : « quelles lignes sont encore en v1 ? »
    op.create_index("ix_tenant_ai_credentials_key_version", "tenant_ai_credentials", ["key_version"])


def downgrade() -> None:
    op.drop_index("ix_tenant_ai_credentials_key_version", table_name="tenant_ai_credentials")
    op.drop_table("tenant_ai_credentials")
    op.drop_table("tenant_ai_configs")
