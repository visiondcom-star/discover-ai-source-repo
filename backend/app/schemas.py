"""Pydantic schemas for request/response validation."""
import re
from datetime import datetime
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, EmailStr, Field, ConfigDict, field_validator, model_validator
from uuid import UUID


from app.constants import (
    CATEGORY_STATUSES,
    PARENT_FAMILIES,
    RESEARCH_COLLECTION_JOB_STATUSES,
    RESEARCH_DOCUMENT_STATUSES,
    RESEARCH_JOB_STATUSES,
    RESEARCH_SOURCE_TYPES,
    RESEARCH_TRIGGER_TYPES,
)


def _pattern(values: tuple[str, ...]) -> str:
    """Builds an anchored alternation pattern from a fixed value set."""
    return "^(?:" + "|".join(values) + ")$"


# Codes de langue Wikimedia acceptés (fr, en, zh-min-nan...).
_WIKI_LANG_RE = re.compile(r"[a-z]{2,3}(?:-[a-z]+)?")



# ============= Tenant Schemas =============
class TenantBase(BaseModel):
    slug: str = Field(..., min_length=2, max_length=50)
    name: str = Field(..., min_length=2, max_length=100)
    country_code: Optional[str] = Field(None, pattern=r"^[A-Za-z]{2}$")
    default_language: str = "fr"
    supported_languages: List[str] = ["fr", "ar", "en"]
    default_currency: str  # required — each tenant must declare its currency
    primary_color: str = "#006233"
    secondary_color: str = "#FFFFFF"
    is_active: bool = True
    config: Dict[str, Any] = {}

    @field_validator("country_code")
    @classmethod
    def normalize_country_code(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        return v.upper()


class TenantCreate(TenantBase):
    pass


class TenantUpdate(BaseModel):
    name: Optional[str] = None
    country_code: Optional[str] = Field(None, pattern=r"^[A-Za-z]{2}$")
    default_language: Optional[str] = None
    supported_languages: Optional[List[str]] = None
    default_currency: Optional[str] = None
    primary_color: Optional[str] = None
    secondary_color: Optional[str] = None
    config: Optional[Dict[str, Any]] = None

    @field_validator("country_code")
    @classmethod
    def normalize_country_code(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        return v.upper()


class TenantResponse(TenantBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    country_code: Optional[str] = None
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


# ============= Tenant Category Schemas =============
class TenantCategoryBase(BaseModel):
    slug: str = Field(..., min_length=2, max_length=50)
    label: str = Field(..., min_length=2, max_length=100)
    parent_family: Optional[str] = Field(None, max_length=50)  # Niveau 1 (macro-famille)
    icon_suggestion: Optional[str] = None
    description: Optional[str] = None
    display_order: int = 0
    ai_generated: bool = True


class TenantCategoryCreate(TenantCategoryBase):
    pass


class TenantCategoryStatusUpdate(BaseModel):
    """Manual lifecycle transition (admin validation endpoint).

    proposed → active (publish), proposed → rejected (discard),
    active → rejected (retire). No self-transition, no resurrect.
    """
    status: str = Field(..., pattern=_pattern(CATEGORY_STATUSES))


class TenantCategoryResponse(TenantCategoryBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tenant_id: UUID
    status: str = Field(..., pattern=_pattern(CATEGORY_STATUSES))
    confidence: Optional[float] = None


# ============= Research Pipeline Schemas =============
class ResearchDocumentIngest(BaseModel):
    """Payload of POST /tenants/research/ingest (admin) — one raw document.

    The service normalizes, hashes and dedups; the client only needs to
    hand over the text and where it came from.
    """
    source_type: str = Field(..., pattern=_pattern(RESEARCH_SOURCE_TYPES))
    source_url: Optional[str] = Field(None, max_length=500)
    raw_text: str = Field(..., min_length=50)
    language: Optional[str] = Field(None, max_length=10)


class ResearchDocumentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tenant_id: UUID
    source_type: str = Field(..., pattern=_pattern(RESEARCH_SOURCE_TYPES))
    source_url: Optional[str] = None
    language: Optional[str] = None
    license: Optional[str] = None
    attribution: Optional[str] = None
    status: str = Field(..., pattern=_pattern(RESEARCH_DOCUMENT_STATUSES))
    content_hash: str
    collected_at: datetime
    created_at: datetime
    # Never expose raw_text in list responses — it can be hundreds of KB;
    # GET /{id}/raw serves it explicitly.
    title: Optional[str] = None


class CategoryCandidate(BaseModel):
    """Une proposition de catégorie Niveau 2 extraite par le LLM."""
    label: str = Field(..., min_length=2, max_length=80)
    description: str = Field(..., min_length=10, max_length=500)
    parent_level1_id: Optional[str] = None
    mapping_confidence: float = Field(..., ge=0.0, le=1.0)
    category_confidence: float = Field(..., ge=0.0, le=1.0)
    suggested_icon: Optional[str] = None
    source_document_ids: list[UUID] = Field(..., min_length=1)

    @field_validator("parent_level1_id")
    @classmethod
    def parent_must_be_known_or_null(cls, v, info):
        allowed = (info.context or {}).get("level1_ids") or []
        if v is not None and v not in allowed:
            raise ValueError(f"parent_level1_id '{v}' hors de la liste fermée")
        return v


class ResearchRunRequest(BaseModel):
    """Payload of POST /tenants/{tenant_id}/research/run."""
    trigger_type: str = Field(
        default="manual_refresh", pattern=_pattern(RESEARCH_TRIGGER_TYPES)
    )


class ResearchJobResponse(BaseModel):
    """Result of POST /tenants/research/run and GET .../research/jobs/{id}.

    Mirrors mobile's ResearchJob.fromJson() field-for-field — keep the two
    in sync if either changes.
    """
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tenant_id: UUID
    trigger_type: str = Field(..., pattern=_pattern(RESEARCH_TRIGGER_TYPES))
    status: str = Field(..., pattern=_pattern(RESEARCH_JOB_STATUSES))
    started_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None
    categories_proposed: int = 0
    categories_auto_published: int = 0
    categories_pending_review: int = 0
    error_message: Optional[str] = None
    created_at: datetime


class ResearchCollectionJobStartRequest(BaseModel):
    """Payload de POST /tenants/{tenant_id}/research/collection/run.

    Tous les champs sont optionnels : sans `territory` le runner collecte le nom
    du tenant, sans `languages` les projets fr + en.
    """
    territory: Optional[str] = Field(None, min_length=1, max_length=100)
    languages: Optional[List[str]] = None

    @field_validator("languages")
    @classmethod
    def _validate_languages(cls, value: Optional[List[str]]) -> Optional[List[str]]:
        """Codes de langue Wikimedia (`fr`, `en`, `zh-min-nan`...).

        Validés ici pour que le runner ne lève pas ValueError en pleine
        collecte : `WikimediaClient.fetch_page` valide `lang`, et un code
        invalide ferait échouer tout le job au lieu d'une seule cible.
        """
        if value is None:
            return None
        normalized: List[str] = []
        for lang in value:
            candidate = (lang or "").strip()
            if not _WIKI_LANG_RE.fullmatch(candidate):
                raise ValueError(
                    f"Code de langue Wikimedia invalide : {lang!r} "
                    "(attendu : 2-3 lettres minuscules, ex. 'fr', 'en', 'zh-min-nan')"
                )
            if candidate not in normalized:
                normalized.append(candidate)
        if not normalized:
            raise ValueError("'languages' ne peut pas être vide")
        return normalized


class ResearchCollectionJobResponse(BaseModel):
    """Résultat de POST /tenants/{tenant_id}/research/collection/run et de
    GET .../research/collection/jobs/{job_id}."""
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tenant_id: UUID
    status: str = Field(..., pattern=_pattern(RESEARCH_COLLECTION_JOB_STATUSES))
    started_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None
    documents_fetched: int = 0
    documents_new: int = 0
    documents_duplicate: int = 0
    documents_failed: int = 0
    error_message: Optional[str] = None
    params: Dict[str, Any] = {}
    created_at: datetime


# ============= Research Source Config Schemas =============
class ResearchSourceConfigCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    url: str = Field(..., max_length=500, pattern=r"^https?://[^\s/$.?#].[^\s]*$")
    source_type: str = Field(default="office_tourisme", pattern=_pattern(RESEARCH_SOURCE_TYPES))
    enabled: bool = True
    config: Dict[str, Any] = {}


class ResearchSourceConfigUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    url: Optional[str] = Field(None, max_length=500, pattern=r"^https?://[^\s/$.?#].[^\s]*$")
    source_type: Optional[str] = Field(None, pattern=_pattern(RESEARCH_SOURCE_TYPES))
    enabled: Optional[bool] = None
    config: Optional[Dict[str, Any]] = None

    @model_validator(mode="after")
    def reject_explicit_nulls(self):
        for field in self.model_fields_set:
            if getattr(self, field) is None:
                raise ValueError(f"'{field}' ne peut pas être null")
        return self


class ResearchSourceConfigResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tenant_id: Optional[UUID] = None
    country_code: Optional[str] = None
    name: str
    url: str
    source_type: str
    enabled: bool
    config: Dict[str, Any]
    created_at: datetime
    updated_at: Optional[datetime] = None


# ============= POI Schemas =============
class POIBase(BaseModel):
    name: str = Field(..., min_length=2, max_length=200)
    description: Optional[str] = None
    city: str = Field(..., min_length=2, max_length=100)
    categories: List[str] = Field(..., min_length=1)
    experiences: List[str] = Field(default_factory=list)      # Niveau 3 (verbes d'action)
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
    categories: Optional[List[str]] = Field(None, min_length=1)
    experiences: Optional[List[str]] = None
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
    categories: List[str] = Field(..., min_length=1)
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


# ============= Promotion Schemas =============
class PromotionBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    subtitle: Optional[str] = None
    image_url: str = Field(..., min_length=1, max_length=500)
    cta_label: Optional[str] = Field(None, max_length=50)
    link_type: Optional[str] = Field(None, pattern="^(poi|trip|external|none)$")
    link_target: Optional[str] = Field(None, max_length=500)
    priority: int = 0
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    is_active: bool = True


class PromotionCreate(PromotionBase):
    pass


class PromotionUpdate(BaseModel):
    title: Optional[str] = None
    subtitle: Optional[str] = None
    image_url: Optional[str] = None
    cta_label: Optional[str] = None
    link_type: Optional[str] = Field(None, pattern="^(poi|trip|external|none)$")
    link_target: Optional[str] = None
    priority: Optional[int] = None
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    is_active: Optional[bool] = None


class PromotionResponse(PromotionBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tenant_id: UUID
    created_at: datetime
    updated_at: datetime


class PromotionListResponse(BaseModel):
    items: List[PromotionResponse]
    total: int


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


class TenantAIConfigUpdate(BaseModel):
    """Corps de PUT /tenants/{tenant_id}/ai-config (upsert)."""
    primary_provider: str = Field(..., min_length=2, max_length=32)
    fallback_provider: Optional[str] = Field(None, max_length=32)
    models: Dict[str, str] = {}          # ex: {"chat": "gpt-4o-mini", "research": "gpt-4o"}
    default_params: Dict[str, Any] = {}  # ex: {"temperature": 0.7, "max_tokens": 800}
    enabled_features: List[str] = ["chat", "recommendation"]
    monthly_spend_limit_usd: Optional[float] = Field(None, ge=0)


class TenantAIConfigResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tenant_id: UUID
    primary_provider: str
    fallback_provider: Optional[str] = None
    models: Dict[str, str]
    default_params: Dict[str, Any]
    enabled_features: List[str]
    monthly_spend_limit_usd: Optional[float] = None
    created_at: datetime
    updated_at: datetime


class TenantAICredentialCreate(BaseModel):
    """Corps de PUT /tenants/{tenant_id}/ai-config/credentials/{provider}.
    La clé en clair n'apparaît que dans cette requête ; jamais dans une réponse."""
    api_key: str = Field(..., min_length=8)


class ProviderTestResult(BaseModel):
    """Réponse de POST .../credentials/{provider}/test.
    `reason` est une des valeurs : None (succès), "no_credential",
    "credential_unreadable", "invalid_api_key", "permission_denied",
    "model_unavailable", "quota_exceeded", "network_error", "provider_error",
    "unknown_error", "test_not_implemented_for_provider"."""
    # `model_tested` ne doit pas déclencher l'avertissement de namespace protégé
    # « model_ » de pydantic.
    model_config = ConfigDict(protected_namespaces=())

    provider: str
    connected: bool
    reason: Optional[str] = None
    model_tested: Optional[str] = None


class TenantAICredentialResponse(BaseModel):
    """Ne contient jamais encrypted_key ni la clé en clair — seulement ses 4 derniers
    caractères, pour affichage admin (ex. 'sk-...1234')."""
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tenant_id: UUID
    provider: str
    key_last4: str
    key_version: int
    created_at: datetime
    rotated_at: Optional[datetime] = None
