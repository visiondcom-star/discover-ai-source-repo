"""initial schema

Revision ID: 0001_initial
Revises:
Create Date: 2026-08-23

Full initial schema matching app.models exactly (SQLAlchemy default naming
convention for indexes: ix_<table>_<column>).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

from pgvector.sqlalchemy import Vector

# revision identifiers, used by Alembic.
revision: str = "0001_initial"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # pgvector extension (superuser — the postgres container user is one).
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")

    op.create_table(
        "tenants",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("slug", sa.String(50), nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("default_language", sa.String(10)),
        sa.Column("supported_languages", sa.ARRAY(sa.String())),
        sa.Column("default_currency", sa.String(10)),
        sa.Column("primary_color", sa.String(7)),
        sa.Column("secondary_color", sa.String(7)),
        sa.Column("is_active", sa.Boolean()),
        sa.Column("config", sa.JSON()),
        sa.Column("created_at", sa.DateTime()),
    )
    op.create_index("ix_tenants_slug", "tenants", ["slug"], unique=True)

    op.create_table(
        "users",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", UUID(as_uuid=True), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("hashed_password", sa.String(255), nullable=False),
        sa.Column("full_name", sa.String(100)),
        sa.Column("is_active", sa.Boolean()),
        sa.Column("is_admin", sa.Boolean()),
        sa.Column("preferences", sa.JSON()),
        sa.Column("created_at", sa.DateTime()),
        sa.UniqueConstraint("tenant_id", "email", name="uq_user_tenant_email"),
    )
    op.create_index("ix_users_tenant_id", "users", ["tenant_id"])
    op.create_index("ix_users_email", "users", ["email"])

    op.create_table(
        "pois",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", UUID(as_uuid=True), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("slug", sa.String(100), nullable=False),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("description", sa.Text()),
        sa.Column("city", sa.String(100), nullable=False),
        sa.Column("category", sa.String(50), nullable=False),
        sa.Column("duration_minutes", sa.Integer()),
        sa.Column("price_range", sa.String(20)),
        sa.Column("latitude", sa.Float()),
        sa.Column("longitude", sa.Float()),
        sa.Column("address", sa.String(255)),
        sa.Column("images", sa.ARRAY(sa.String())),
        sa.Column("tags", sa.ARRAY(sa.String())),
        sa.Column("accessibility", sa.ARRAY(sa.String())),
        sa.Column("opening_hours", sa.JSON()),
        sa.Column("average_rating", sa.Float()),
        sa.Column("review_count", sa.Integer()),
        sa.Column("is_verified", sa.Boolean()),
        sa.Column("is_active", sa.Boolean()),
        sa.Column("embedding", Vector(1536)),
        sa.Column("created_at", sa.DateTime()),
        sa.Column("updated_at", sa.DateTime()),
    )
    op.create_index("ix_pois_tenant_id", "pois", ["tenant_id"])
    op.create_index("ix_pois_slug", "pois", ["slug"])
    op.create_index("ix_pois_city", "pois", ["city"])
    op.create_index("ix_pois_category", "pois", ["category"])
    op.create_index("ix_pois_average_rating", "pois", ["average_rating"])

    op.create_table(
        "trips",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", UUID(as_uuid=True), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("description", sa.Text()),
        sa.Column("num_days", sa.Integer()),
        sa.Column("budget_level", sa.String(20)),
        sa.Column("budget_currency", sa.String(10)),
        sa.Column("travel_style", sa.String(50)),
        sa.Column("interests", sa.ARRAY(sa.String())),
        sa.Column("accessibility_needs", sa.ARRAY(sa.String())),
        sa.Column("dietary_restrictions", sa.ARRAY(sa.String())),
        sa.Column("group_type", sa.String(50)),
        sa.Column("children", sa.Boolean()),
        sa.Column("status", sa.String(50)),
        sa.Column("start_date", sa.DateTime()),
        sa.Column("end_date", sa.DateTime()),
        sa.Column("total_cost_estimate", sa.Float()),
        sa.Column("metadata", sa.JSON()),
        sa.Column("created_at", sa.DateTime()),
        sa.Column("updated_at", sa.DateTime()),
    )
    op.create_index("ix_trips_tenant_id", "trips", ["tenant_id"])

    op.create_table(
        "trip_items",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("trip_id", UUID(as_uuid=True), sa.ForeignKey("trips.id"), nullable=False),
        sa.Column("poi_id", UUID(as_uuid=True), sa.ForeignKey("pois.id"), nullable=False),
        sa.Column("day_number", sa.Integer()),
        sa.Column("order_index", sa.Integer()),
        sa.Column("start_time", sa.DateTime()),
        sa.Column("end_time", sa.DateTime()),
        sa.Column("notes", sa.Text()),
    )

    op.create_table(
        "bookings",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", UUID(as_uuid=True), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("poi_id", UUID(as_uuid=True), sa.ForeignKey("pois.id"), nullable=False),
        sa.Column("adapter_type", sa.String(50), nullable=False),
        sa.Column("external_id", sa.String(255)),
        sa.Column("status", sa.String(50)),
        sa.Column("consent_given", sa.Boolean()),
        sa.Column("consent_timestamp", sa.DateTime()),
        sa.Column("price", sa.Float()),
        sa.Column("currency", sa.String(10)),
        sa.Column("booking_data", sa.JSON()),
        sa.Column("created_at", sa.DateTime()),
        sa.Column("updated_at", sa.DateTime()),
    )
    op.create_index("ix_bookings_tenant_id", "bookings", ["tenant_id"])

    op.create_table(
        "reviews",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", UUID(as_uuid=True), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("poi_id", UUID(as_uuid=True), sa.ForeignKey("pois.id"), nullable=False),
        sa.Column("rating", sa.Integer(), nullable=False),
        sa.Column("comment", sa.Text()),
        sa.Column("created_at", sa.DateTime()),
        sa.Column("updated_at", sa.DateTime()),
        sa.UniqueConstraint("tenant_id", "user_id", "poi_id", name="uq_review_tenant_user_poi"),
    )
    op.create_index("ix_reviews_tenant_id", "reviews", ["tenant_id"])
    op.create_index("ix_reviews_user_id", "reviews", ["user_id"])
    op.create_index("ix_reviews_poi_id", "reviews", ["poi_id"])
    op.create_index("ix_reviews_rating", "reviews", ["rating"])
    op.create_index("ix_reviews_created_at", "reviews", ["created_at"])

    op.create_table(
        "analytics_events",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", UUID(as_uuid=True), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id")),
        sa.Column("event_type", sa.String(100), nullable=False),
        sa.Column("event_data", sa.JSON()),
        sa.Column("session_id", sa.String(255)),
        sa.Column("ip_address", sa.String(45)),
        sa.Column("user_agent", sa.String(500)),
        sa.Column("created_at", sa.DateTime()),
    )
    op.create_index("ix_analytics_events_tenant_id", "analytics_events", ["tenant_id"])
    op.create_index("ix_analytics_events_event_type", "analytics_events", ["event_type"])

    op.create_table(
        "chat_messages",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", UUID(as_uuid=True), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("role", sa.String(20), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("context", sa.JSON()),
        sa.Column("created_at", sa.DateTime()),
    )
    op.create_index("ix_chat_messages_tenant_id", "chat_messages", ["tenant_id"])


def downgrade() -> None:
    op.drop_table("chat_messages")
    op.drop_table("analytics_events")
    op.drop_table("reviews")
    op.drop_table("bookings")
    op.drop_table("trip_items")
    op.drop_table("trips")
    op.drop_table("pois")
    op.drop_table("users")
    op.drop_table("tenants")
    op.execute("DROP EXTENSION IF EXISTS vector")


