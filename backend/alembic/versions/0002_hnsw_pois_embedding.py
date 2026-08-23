"""hnsw index on pois.embedding

Revision ID: 0002_hnsw_pois_embedding
Revises: 0001_initial
Create Date: 2026-08-23

Adds an HNSW index over pois.embedding so tenant-scoped cosine KNN queries
(ORDER BY embedding <=> :query) stay fast as the catalog grows, instead of
scanning every row.
"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0002_hnsw_pois_embedding"
down_revision: Union[str, None] = "0001_initial"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # IF NOT EXISTS keeps this idempotent for databases where the index was
    # created out-of-band (e.g. manual tuning sessions).
    op.execute(
        """
        CREATE INDEX IF NOT EXISTS ix_pois_embedding_hnsw
        ON pois USING hnsw (embedding vector_cosine_ops)
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_pois_embedding_hnsw")
