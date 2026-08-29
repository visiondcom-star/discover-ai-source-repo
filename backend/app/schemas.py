"""Pydantic schemas for request/response validation."""
from datetime import datetime
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, EmailStr, Field, ConfigDict
from uuid import UUID


# ============= Tenant Schemas =============
class TenantBase(BaseModel):
    slug: str = Field(..., min_length=2, max_length=50)
    name: str = Field(..., min_length=2, max_length=100)
    default_language: str = "fr"
    supported_languages: List[str] = ["fr", "ar", "en"]
    default_currency: str  # required — each tenant must declare its currency
    primary_color: str = "#006233"
    secondary_color: str = "#FFFFFF"
    is_active: bool = True
    config: Dict[str, Any] = {}


class TenantCreate(TenantBase):
    pass


class TenantUpdate(BaseModel):
    name: Optional[str] = None
    default_language: Optional[str] = None
    supported_languages: Optional[List[str]] = None
    default_currency: Optional[str] = None
    primary_color: Optional[str] = None
    secondary_color: Optional[str] = None
    is_active: Optional[bool] = None
    config: Optional[Dict[str, Any]] = None


class TenantResponse(TenantBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    created_at: datetime


# ============= Auth Schemas =============
class UserRegister(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=6)
    full_name: Optional[str] = None


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: str
    full_name: Optional[str]
    is_active: bool
    is_admin: bool
    preferences: Dict[str, Any]
    created_at: datetime


# ============= POI Schemas =============
class POIBase(BaseModel):
    name: str = Field(..., min_length=2, max_length=200)
    description: Optional[str] = None
    city: str = Field(..., min_length=2, max_length=100)
    category: str = Field(..., pattern="^(historical|nature|culture|adventure|food|shopping)$")
    duration_minutes: int = Field(default=60, ge=15, le=1440)
    price_range: str = Field(default="free", pattern="^(free|low|medium|high)$")
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    address: Optional[str] = None
    images: List[str] = []
    tags: List[str] = []
    accessibility: List[str] = []
    opening_hours: Dict[str, Any] = {}


class POICreate(POIBase):
    pass


class POIUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    city: Optional[str] = None
    category: Optional[str] = None
    duration_minutes: Optional[int] = None
    price_range: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    address: Optional[str] = None
    images: Optional[List[str]] = None
    tags: Optional[List[str]] = None
    accessibility: Optional[List[str]] = None
    opening_hours: Optional[Dict[str, Any]] = None
    is_active: Optional[bool] = None


class POIResponse(POIBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    slug: str
    tenant_id: UUID
    is_verified: bool
    is_active: bool
    average_rating: Optional[float] = None
    review_count: int = 0
    created_at: datetime
    updated_at: datetime


class POIListResponse(BaseModel):
    items: List[POIResponse]
    total: int
    page: int
    page_size: int


# ============= Trip Schemas =============
class TripGenerateRequest(BaseModel):
    interests: List[str] = []
    budget_level: str = Field(default="medium", pattern="^(low|medium|high)$")
    num_days: int = Field(default=3, ge=1, le=14)
    budget_currency: Optional[str] = None
    travel_style: str = Field(default="balanced", pattern="^(relaxed|balanced|intensive)$")
    accessibility_needs: List[str] = []
    dietary_restrictions: List[str] = []
    group_type: str = Field(default="solo", pattern="^(solo|couple|family|friends)$")
    children: bool = False
    city: Optional[str] = None


class TripItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    poi_id: UUID
    day_number: int
    order_index: int
    start_time: Optional[datetime]
    end_time: Optional[datetime]
    notes: Optional[str]
    poi: Optional[POIResponse] = None


class TripResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tenant_id: UUID
    user_id: UUID
    title: str
    description: Optional[str]
    num_days: int
    budget_level: str
    budget_currency: str
    travel_style: str
    interests: List[str]
    group_type: str
    children: bool
    status: str
    total_cost_estimate: Optional[float]
    items: List[TripItemResponse] = []
    created_at: datetime
    updated_at: datetime


# ============= Chat Schemas =============
class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    context: Optional[Dict[str, Any]] = None


class ChatResponse(BaseModel):
    message: str
    suggestions: List[str] = []
    context: Dict[str, Any] = {}


# ============= RAG Schemas =============
class RAGSearchRequest(BaseModel):
    query: str = Field(..., min_length=1)
    top_k: int = Field(default=5, ge=1, le=20)


class RAGSearchResult(BaseModel):
    poi_id: UUID
    name: str
    score: float
    description: Optional[str]


class RAGSearchResponse(BaseModel):
    results: List[RAGSearchResult]
    query: str


# ============= Content Pipeline Schemas =============
class ContentImportResponse(BaseModel):
    imported: int
    errors: int
    details: List[Dict[str, Any]]


class ContentValidationRequest(BaseModel):
    poi_ids: List[UUID]


# ============= Context Schemas =============
class WeatherResponse(BaseModel):
    city: str
    temperature: float
    condition: str
    humidity: int
    wind_speed: float
    forecast: List[Dict[str, Any]] = []


class ContextEventCreate(BaseModel):
    event_type: str
    title: str
    description: Optional[str] = None
    severity: str = "info"  # info, warning, critical
    location: Optional[str] = None
    metadata: Dict[str, Any] = {}


# ============= Analytics Schemas =============
class AnalyticsTrackRequest(BaseModel):
    event_type: str
    event_data: Dict[str, Any] = {}
    session_id: Optional[str] = None


class DashboardOverview(BaseModel):
    total_users: int
    total_pois: int
    total_trips: int
    total_bookings: int
    active_users_today: int
    events_today: int


# ============= Booking Schemas =============
class BookingCreate(BaseModel):
    poi_id: UUID
    adapter_type: str = Field(..., pattern="^(hotel|restaurant|tour|transport)$")
    booking_data: Dict[str, Any] = {}


class BookingResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tenant_id: UUID
    user_id: UUID
    poi_id: UUID
    adapter_type: str
    external_id: Optional[str]
    status: str
    consent_given: bool
    price: Optional[float]
    currency: str
    created_at: datetime


class ConsentRequest(BaseModel):
    # No default: a request that omits `consent` must be rejected by Pydantic
    # validation (422) rather than silently treated as consent given. The
    # client always sends this explicitly (see mobile BookingProvider.
    # giveConsent) — this only closes the gap for any other caller.
    consent: bool


# ============= Review Schemas =============
class ReviewCreate(BaseModel):
    rating: int = Field(..., ge=1, le=5)
    comment: Optional[str] = Field(default=None, max_length=2000)


class ReviewUpdate(BaseModel):
    rating: Optional[int] = Field(default=None, ge=1, le=5)
    comment: Optional[str] = Field(default=None, max_length=2000)


class ReviewResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tenant_id: UUID
    user_id: UUID
    poi_id: UUID
    rating: int
    comment: Optional[str]
    created_at: datetime
    updated_at: datetime
