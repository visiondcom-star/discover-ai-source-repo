"""poi categories array

Revision ID: 0004_poi_categories_array
Revises: 0003_promotions
Create Date: 2026-09-11

Replaces POI.category (VARCHAR(50)) with POI.categories (VARCHAR[]).
Migrates existing data so each POI's categories becomes ARRAY[category],
then drops the legacy category column and its index.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0004_poi_categories_array"
down_revision: Union[str, None] = "0003_promotions"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Add categories array column (nullable initially so existing rows can be updated)
    op.add_column("pois", sa.Column("categories", postgresql.ARRAY(sa.String()), nullable=True))

    # 2. Migrate existing data: categories = ARRAY[category]
    op.execute("UPDATE pois SET categories = ARRAY[category] WHERE category IS NOT NULL")
    op.execute("UPDATE pois SET categories = '{}' WHERE categories IS NULL")

    # 3. Enforce NOT NULL and default empty list
    op.alter_column(
        "pois",
        "categories",
        nullable=False,
        server_default=sa.text("'{}'::varchar[]"),
    )

    # 4. Create GIN index for efficient overlap (&&) and containment (@>) queries
    op.create_index(
        "ix_pois_categories_gin",
        "pois",
        ["categories"],
        postgresql_using="gin",
    )

    # 5. Drop legacy index and column
    op.drop_index("ix_pois_category", table_name="pois")
    op.drop_column("pois", "category")


def downgrade() -> None:
    # 1. Re-add category column
    op.add_column("pois", sa.Column("category", sa.String(length=50), nullable=True))

    # 2. Revert data: take first category from array if present, else fallback
    op.execute(
        "UPDATE pois SET category = categories[1] WHERE categories IS NOT NULL AND array_length(categories, 1) > 0"
    )
    op.execute("UPDATE pois SET category = 'other' WHERE category IS NULL")

    # 3. Restore NOT NULL constraint and index
    op.alter_column("pois", "category", nullable=False)
    op.create_index("ix_pois_category", "pois", ["category"])

    # 4. Drop GIN index and categories column
    op.drop_index("ix_pois_categories_gin", table_name="pois", postgresql_using="gin")
    op.drop_column("pois", "categories")
