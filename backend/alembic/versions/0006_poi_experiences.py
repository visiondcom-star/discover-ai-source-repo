"""experiences array on pois

Revision ID: 0006_poi_experiences
Revises: 0005_tenant_categories
Create Date: 2026-09-12

Adds the POI experiences array declared by the POI model.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0006_poi_experiences"
down_revision: Union[str, None] = "0005_tenant_categories"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add nullable first so existing POIs can be backfilled before enforcing
    # the same list-shaped invariant as the Pydantic response schema.
    op.add_column(
        "pois",
        sa.Column("experiences", postgresql.ARRAY(sa.String()), nullable=True),
    )
    op.execute("UPDATE pois SET experiences = '{}' WHERE experiences IS NULL")
    op.alter_column(
        "pois",
        "experiences",
        nullable=False,
        server_default=sa.text("'{}'::varchar[]"),
    )


def downgrade() -> None:
    op.drop_column("pois", "experiences")
