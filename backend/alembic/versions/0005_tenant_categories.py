"""tenant categories table

Revision ID: 0005_tenant_categories
Revises: 0004_poi_categories_array
Create Date: 2026-09-11

Creates the tenant_categories table backing TenantCategory (backend/app/models.py).
The model was added in commit 99351ea without its migration — this fixes
that gap. Without this table, app startup's init_db() crashes on the
first SELECT against tenant_categories (UndefinedTableError), which
looked like a hang because the error was only surfaced when called
directly outside the lifespan's swallowed-exception context.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0005_tenant_categories"
down_revision: Union[str, None] = "0004_poi_categories_array"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "tenant_categories",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("parent_family", sa.String(50), nullable=True),
        sa.Column("slug", sa.String(50), nullable=False),
        sa.Column("label", sa.String(100), nullable=False),
        sa.Column("icon_suggestion", sa.String(50), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("display_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("ai_generated", sa.Boolean(), nullable=False, server_default=sa.true()),
    )
    op.create_index("ix_tenant_categories_tenant_id", "tenant_categories", ["tenant_id"])
    op.create_index("ix_tenant_categories_parent_family", "tenant_categories", ["parent_family"])
    op.create_unique_constraint(
        "uq_tenant_category_slug", "tenant_categories", ["tenant_id", "slug"]
    )


def downgrade() -> None:
    op.drop_constraint("uq_tenant_category_slug", "tenant_categories", type_="unique")
    op.drop_index("ix_tenant_categories_parent_family", table_name="tenant_categories")
    op.drop_index("ix_tenant_categories_tenant_id", table_name="tenant_categories")
    op.drop_table("tenant_categories")
