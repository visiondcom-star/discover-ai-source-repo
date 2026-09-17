"""research pipeline: destination documents + category lifecycle

Revision ID: 0007_research_pipeline
Revises: 0006_poi_experiences
Create Date: 2026-09-15

Backs the AI research pipeline (Recherche → Ingestion → Extraction):
- destination_research_documents: raw ingested documents per tenant.
  Dedup via (tenant_id, content_hash) unique constraint — re-running the
  pipeline over the same sources is idempotent.
- tenant_categories gains the proposal lifecycle: status
  ('proposed'|'active'|'rejected', server_default 'active' so existing
  rows keep working unchanged), LLM confidence, provenance FK to the
  source document, and a pgvector embedding for near-duplicate detection
  at proposal time ("Randonnée" vs "Trekking").
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from pgvector.sqlalchemy import Vector
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0007_research_pipeline"
down_revision: Union[str, None] = "0006_poi_experiences"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "destination_research_documents",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("source_type", sa.String(20), nullable=False),
        sa.Column("source_url", sa.String(500), nullable=True),
        sa.Column("raw_text", sa.Text(), nullable=False),
        sa.Column("language", sa.String(10), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="raw"),
        sa.Column("content_hash", sa.String(64), nullable=False),
        sa.Column("collected_at", sa.DateTime(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("tenant_id", "content_hash", name="uq_research_doc_tenant_hash"),
    )
    op.create_index(
        "ix_destination_research_documents_tenant_id",
        "destination_research_documents",
        ["tenant_id"],
    )
    op.create_index(
        "ix_destination_research_documents_status",
        "destination_research_documents",
        ["status"],
    )

    op.add_column(
        "tenant_categories",
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
    )
    op.add_column(
        "tenant_categories",
        sa.Column("confidence", sa.Float(), nullable=True),
    )
    op.add_column(
        "tenant_categories",
        sa.Column(
            "research_document_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("destination_research_documents.id"),
            nullable=True,
        ),
    )
    op.add_column(
        "tenant_categories",
        sa.Column("embedding", Vector(1536), nullable=True),
    )
    op.create_index(
        "ix_tenant_categories_status", "tenant_categories", ["status"]
    )


def downgrade() -> None:
    op.drop_index("ix_tenant_categories_status", table_name="tenant_categories")
    op.drop_column("tenant_categories", "embedding")
    op.drop_column("tenant_categories", "research_document_id")
    op.drop_column("tenant_categories", "confidence")
    op.drop_column("tenant_categories", "status")
    op.drop_index(
        "ix_destination_research_documents_status",
        table_name="destination_research_documents",
    )
    op.drop_index(
        "ix_destination_research_documents_tenant_id",
        table_name="destination_research_documents",
    )
    op.drop_table("destination_research_documents")