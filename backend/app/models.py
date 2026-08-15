"""SQLAlchemy ORM models with multi-tenant isolation."""
import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Float, Boolean, DateTime, Text, ForeignKey, JSON, ARRAY
from sqlalchemy.dialects.postgresql import UUID
from pgvector.sqlalchemy import Vector
from sqlalchemy.orm import relationship
from app.database import Base


def generate_uuid():
    return str(uuid.uuid4())


class Tenant(Base):
    __tablename__ = "tenants"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    slug = Column(String(50), unique=True, nullable=False, index=True)
    name = Column(String(100), nullable=False)
    default_language = Column(String(10), default="fr")
    supported_languages = Column(ARRAY(String), default=list)
    default_currency = Column(String(10), default="DZD")
    primary_color = Column(String(7), default="#006233")
    secondary_color = Column(String(7), default="#FFFFFF")
    is_active = Column(Boolean, default=True)
    config = Column(JSON, default=dict)
    created_at = Column(DateTime, default=datetime.utcnow)

    users = relationship("User", back_populates="tenant")
    pois = relationship("POI", back_populates="tenant")
    trips = relationship("Trip", back_populates="tenant")


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, index=True)
    email = Column(String(255), nullable=False, index=True)
    hashed_password = Column(String(255), nullable=False)
    full_name = Column(String(100), nullable=True)
    is_active = Column(Boolean, default=True)
    is_admin = Column(Boolean, default=False)
    preferences = Column(JSON, default=dict)
    created_at = Column(DateTime, default=datetime.utcnow)

    tenant = relationship("Tenant", back_populates="users")
    trips = relationship("Trip", back_populates="user")
    bookings = relationship("Booking", back_populates="user")

    __table_args__ = (
        # Unique email per tenant
        {"comment": "Unique constraint on email per tenant"},
    )


class POI(Base):
    __tablename__ = "pois"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, index=True)
    slug = Column(String(100), nullable=False, index=True)
    name = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    city = Column(String(100), nullable=False, index=True)
    category = Column(String(50), nullable=False, index=True)  # historical, nature, culture, adventure
    duration_minutes = Column(Integer, default=60)
    price_range = Column(String(20), default="free")  # free, low, medium, high
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    address = Column(String(255), nullable=True)
    images = Column(ARRAY(String), default=list)
    tags = Column(ARRAY(String), default=list)
    accessibility = Column(ARRAY(String), default=list)
    opening_hours = Column(JSON, default=dict)
    is_verified = Column(Boolean, default=False)
    is_active = Column(Boolean, default=True)
    embedding = Column(Vector(1536), nullable=True)  # pgvector, 1536 for text-embedding-3-small
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    tenant = relationship("Tenant", back_populates="pois")
    trip_items = relationship("TripItem", back_populates="poi")


class Trip(Base):
    __tablename__ = "trips"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    num_days = Column(Integer, default=1)
    budget_level = Column(String(20), default="medium")  # low, medium, high
    budget_currency = Column(String(10), default="DZD")
    travel_style = Column(String(50), default="balanced")  # relaxed, balanced, intensive
    interests = Column(ARRAY(String), default=list)
    accessibility_needs = Column(ARRAY(String), default=list)
    dietary_restrictions = Column(ARRAY(String), default=list)
    group_type = Column(String(50), default="solo")  # solo, couple, family, friends
    children = Column(Boolean, default=False)
    status = Column(String(50), default="draft")  # draft, planned, active, completed
    start_date = Column(DateTime, nullable=True)
    end_date = Column(DateTime, nullable=True)
    total_cost_estimate = Column(Float, nullable=True)
    metadata_ = Column("metadata", JSON, default=dict)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    tenant = relationship("Tenant", back_populates="trips")
    user = relationship("User", back_populates="trips")
    items = relationship("TripItem", back_populates="trip", order_by="TripItem.day_number, TripItem.order_index")


class TripItem(Base):
    __tablename__ = "trip_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    trip_id = Column(UUID(as_uuid=True), ForeignKey("trips.id"), nullable=False)
    poi_id = Column(UUID(as_uuid=True), ForeignKey("pois.id"), nullable=False)
    day_number = Column(Integer, default=1)
    order_index = Column(Integer, default=0)
    start_time = Column(DateTime, nullable=True)
    end_time = Column(DateTime, nullable=True)
    notes = Column(Text, nullable=True)

    trip = relationship("Trip", back_populates="items")
    poi = relationship("POI", back_populates="trip_items")


class Booking(Base):
    __tablename__ = "bookings"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    poi_id = Column(UUID(as_uuid=True), ForeignKey("pois.id"), nullable=False)
    adapter_type = Column(String(50), nullable=False)  # hotel, restaurant, tour
    external_id = Column(String(255), nullable=True)
    status = Column(String(50), default="pending")  # pending, confirmed, cancelled
    consent_given = Column(Boolean, default=False)
    consent_timestamp = Column(DateTime, nullable=True)
    price = Column(Float, nullable=True)
    currency = Column(String(10), default="DZD")
    booking_data = Column(JSON, default=dict)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    user = relationship("User", back_populates="bookings")


class AnalyticsEvent(Base):
    __tablename__ = "analytics_events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    event_type = Column(String(100), nullable=False, index=True)
    event_data = Column(JSON, default=dict)
    session_id = Column(String(255), nullable=True)
    ip_address = Column(String(45), nullable=True)
    user_agent = Column(String(500), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class ChatMessage(Base):
    __tablename__ = "chat_messages"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    role = Column(String(20), nullable=False)  # user, assistant, system
    content = Column(Text, nullable=False)
    context = Column(JSON, default=dict)
    created_at = Column(DateTime, default=datetime.utcnow)
