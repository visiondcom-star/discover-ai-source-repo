"""promotions table

Revision ID: 0003_promotions
Revises: 0002_hnsw_pois_embedding
Create Date: 2026-08-29

Adds the promotions table backing the mobile home-screen promo banner
(e.g. "L'Algérie vous attend"). Deliberately not a POI subtype — see the
Promotion model docstring for why.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0003_promotions"
down_revision: Union[str, None] = "0002_hnsw_pois_embedding"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "promotions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("subtitle", sa.Text(), nullable=True),
        sa.Column("image_url", sa.String(500), nullable=False),
        sa.Column("cta_label", sa.String(50), nullable=True),
        sa.Column("link_type", sa.String(20), nullable=True),
        sa.Column("link_target", sa.String(500), nullable=True),
        sa.Column("priority", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("starts_at", sa.DateTime(), nullable=True),
        sa.Column("ends_at", sa.DateTime(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_promotions_tenant_id", "promotions", ["tenant_id"])
    op.create_index("ix_promotions_priority", "promotions", ["priority"])


def downgrade() -> None:
    op.drop_index("ix_promotions_priority", table_name="promotions")
    op.drop_index("ix_promotions_tenant_id", table_name="promotions")
    op.drop_table("promotions")
