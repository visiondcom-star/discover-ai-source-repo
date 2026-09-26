"""SQLAlchemy ORM models with multi-tenant isolation."""
import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Integer, Float, Boolean, DateTime, Text, ForeignKey, JSON, ARRAY, UniqueConstraint, Index, Numeric
from sqlalchemy.dialects.postgresql import UUID
from pgvector.sqlalchemy import Vector
from sqlalchemy.orm import relationship, validates
from app.database import Base


def utcnow() -> datetime:
    """Current UTC instant as a *naive* datetime (tzinfo stripped).

    Convention du projet : toutes les colonnes temporelles sont déclarées
    ``DateTime`` (PostgreSQL ``TIMESTAMP WITHOUT TIME ZONE``) et le driver
    asyncpg refuse les datetimes timezone-aware sur ce type de colonne.
    On garde donc la sémantique naive-UTC, mais via l'API moderne —
    ``datetime.utcnow()`` est déprécié et sera supprimé d'une future
    version de Python.

    Si un jour les colonnes passent en ``DateTime(timezone=True)`` /
    ``TIMESTAMPTZ``, il suffira de retirer le ``.replace(tzinfo=None)``
    ici et aux rares endroits qui utilisent ce helper.

    Note : on utilise ``timezone.utc`` plutôt que l'alias ``datetime.UTC``
    (Python 3.11+) car le venv local peut tourner sous Python 3.9 ; c'est
    aussi la convention de ``app/core/security.py``.
    """
    return datetime.now(timezone.utc).replace(tzinfo=None)


def generate_uuid():
    return str(uuid.uuid4())


class Tenant(Base):
    __tablename__ = "tenants"

    id = Column(UUID(
        as_uuid=True), primary_key=True, default=uuid.uuid4)
    slug = Column(String(50), unique=True, nullable=False, index=True)
    name = Column(String(100), nullable=False)
    default_language = Column(String(10), default="fr")
    supported_languages = Column(ARRAY(String), default=list)
    default_currency = Column(String(10))  # required per-tenant; never a hardcoded literal
    primary_color = Column(String(7), default="#006233")
    secondary_color = Column(String(7), default="#FFFFFF")
    is_active = Column(Boolean, default=True)
    config = Column(JSON, default=dict)
    created_at = Column(DateTime, default=utcnow)

    users = relationship("User", back_populates="tenant")
    pois = relationship("POI", back_populates="tenant")
    trips = relationship("Trip", back_populates="tenant")
    bookings = relationship("Booking", back_populates="tenant")
    reviews = relationship("Review", back_populates="tenant")
    analytics_events = relationship("AnalyticsEvent", back_populates="tenant")
    chat_messages = relationship("ChatMessage", back_populates="tenant")
    promotions = relationship("Promotion", back_populates="tenant")
    tenant_categories = relationship("TenantCategory", back_populates="tenant", cascade="all, delete-orphan")
    research_documents = relationship("DestinationResearchDocument", back_populates="tenant")
    research_jobs = relationship("ResearchJob", back_populates="tenant")


class TenantCategory(Base):
    """Catalogue des catégories disponibles pour un tenant/pays.
    Chaque tenant déclare ses propres slugs/labels/icônes — plus de liste blanche codée en dur.
    Niveau 1: parent_family (culture, nature, histoire, etc.)
    Niveau 2: slug & label (sahara_oasis, casbah_medinas, etc.) déduits par l'IA"""
    __tablename__ = "tenant_categories"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, index=True)
    parent_family = Column(String(50), nullable=True, index=True)  # Niveau 1 (macro-famille globale)
    slug = Column(String(50), nullable=False)                     # Niveau 2 (slug local)
    label = Column(String(100), nullable=False)                   # Niveau 2 (libellé local)
    icon_suggestion = Column(String(50))                          # nom d'icône (ex: "sun", "castle")
    description = Column(Text, nullable=True)                     # Synthèse culturelle de l'IA
    display_order = Column(Integer, default=0)
    ai_generated = Column(Boolean, default=True)

    # Cycle de vie d'une catégorie (pipeline de recherche IA, Principe 5:
    # les propositions LLM n'activent rien seules — 'proposed' reste invisible
    # pour trip planner / filtres POI / chat tant qu'un humain n'a pas
    # validé. 'active' est le défaut : les lignes créées hors pipeline
    # (seed, création manuelle admin) sont immédiatement utilisables.)
    status = Column(String(20), nullable=False, default="active",
                    server_default="active", index=True)  # proposed | active | rejected
    confidence = Column(Float, nullable=True)             # confiance LLM 0..1 (extraction)
    # Provenance : document de recherche d'origine de la proposition.
    research_document_id = Column(
        UUID(as_uuid=True),
        ForeignKey("destination_research_documents.id"),
        nullable=True,
    )
    # Embedding de la description (même dimension que POI.embedding) pour la
    # dédup sémantique à la proposition ("Randonnée" vs "Trekking") et la
    # future recherche. Gated par USE_PGVECTOR côté service.
    embedding = Column(Vector(1536), nullable=True)

    __table_args__ = (
        UniqueConstraint("tenant_id", "slug", name="uq_tenant_category_slug"),
    )

    tenant = relationship("Tenant", back_populates="tenant_categories")


class DestinationResearchDocument(Base):
    """Document brut collecté par le pipeline de recherche destination.

    Niveau 1-2 du pipeline (Recherche → Ingestion) : stockage brut avec
    provenance, avant normalisation/extraction LLM. La dédup basique passe
    par content_hash (sha256 du texte normalisé), unique par tenant —
    relancer le pipeline sur les mêmes sources est donc idempotent.
    """
    __tablename__ = "destination_research_documents"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, index=True)
    # guide | office_tourisme | wiki | autre — valeur contrainte côté
    # schémas Pydantic (pattern), pas de CHECK en DB (style du codebase)
    source_type = Column(String(20), nullable=False)
    # Provenance précise (nullable : sources hors-ligne / docs internes)
    source_url = Column(String(500), nullable=True)
    raw_text = Column(Text, nullable=False)
    language = Column(String(10), nullable=True)                  # détecté à l'ingestion
    # raw | processed | discarded — la normalisation/extraction est en
    # mémoire pendant le run ; 'processed' = le LLM a fini de travailler
    # sur ce document (au moins une passe d'extraction consommée).
    status = Column(String(20), nullable=False, default="raw",
                    server_default="raw", index=True)
    content_hash = Column(String(64), nullable=False)             # sha256 hex
    collected_at = Column(DateTime, default=utcnow)
    created_at = Column(DateTime, default=utcnow)

    __table_args__ = (
        UniqueConstraint("tenant_id", "content_hash", name="uq_research_doc_tenant_hash"),
    )

    tenant = relationship("Tenant", back_populates="research_documents")


class ResearchJob(Base):
    """Trackable job for the AI research pipeline (Niveau 2 dynamique).

    One row per POST /tenants/{id}/research/run, updated in place as a
    FastAPI BackgroundTask progresses it through
    pending -> processing -> done|failed.
    """
    __tablename__ = "research_jobs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, index=True)
    trigger_type = Column(String(20), nullable=False)
    # pending | processing | done | failed — validated via Pydantic pattern,
    # not DB CHECK (codebase convention).
    status = Column(String(20), nullable=False, default="pending",
                    server_default="pending", index=True)
    started_at = Column(DateTime, nullable=True)
    finished_at = Column(DateTime, nullable=True)
    categories_proposed = Column(Integer, nullable=False, default=0, server_default="0")
    categories_auto_published = Column(Integer, nullable=False, default=0, server_default="0")
    categories_pending_review = Column(Integer, nullable=False, default=0, server_default="0")
    error_message = Column(Text, nullable=True)
    created_at = Column(DateTime, default=utcnow)

    __table_args__ = (
        Index("ix_research_jobs_tenant_trigger_created",
              "tenant_id", "trigger_type", "created_at"),
    )

    tenant = relationship("Tenant", back_populates="research_jobs")


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
    created_at = Column(DateTime, default=utcnow)

    tenant = relationship("Tenant", back_populates="users")
    trips = relationship("Trip", back_populates="user")
    bookings = relationship("Booking", back_populates="user")
    reviews = relationship("Review", back_populates="user")
    analytics_events = relationship("AnalyticsEvent", back_populates="user")
    chat_messages = relationship("ChatMessage", back_populates="user")

    __table_args__ = (
        UniqueConstraint("tenant_id", "email", name="uq_user_tenant_email"),
    )


class POI(Base):
    __tablename__ = "pois"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, index=True)
    slug = Column(String(100), nullable=False, index=True)
    name = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    city = Column(String(100), nullable=False, index=True)
    categories = Column(ARRAY(String), nullable=False, default=list)
    experiences = Column(ARRAY(String), default=list)          # Niveau 3: verbes d'action (visiter, randonner, etc.)
    duration_minutes = Column(Integer, default=60)
    price_range = Column(String(20), default="free")  # free, low, medium, high
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    address = Column(String(255), nullable=True)
    images = Column(ARRAY(String), default=list)
    tags = Column(ARRAY(String), default=list)
    accessibility = Column(ARRAY(String), default=list)
    opening_hours = Column(JSON, default=dict)
    average_rating = Column(Float, nullable=True, index=True)
    review_count = Column(Integer, default=0)
    is_verified = Column(Boolean, default=False)
    is_active = Column(Boolean, default=True)
    embedding = Column(Vector(1536), nullable=True)  # pgvector, 1536 for text-embedding-3-small
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

    tenant = relationship("Tenant", back_populates="pois")
    trip_items = relationship("TripItem", back_populates="poi")
    bookings = relationship("Booking", back_populates="poi")
    reviews = relationship("Review", back_populates="poi")


class Promotion(Base):
    """Home-screen promo banner content (e.g. "L'Algérie vous attend").

    Deliberately decoupled from POI: a promotion is marketing content, not
    a place — it may point at a POI, a Trip template, or nowhere (pure
    branding banner), and it has its own scheduling/priority concerns that
    don't belong on POI.
    """
    __tablename__ = "promotions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, index=True)
    title = Column(String(200), nullable=False)
    subtitle = Column(Text, nullable=True)
    image_url = Column(String(500), nullable=False)
    cta_label = Column(String(50), nullable=True)
    # Deep-link target: kept as a loose (type, id) pair rather than a hard FK
    # so a promotion can point at a POI, a Trip template, an external URL,
    # or nothing at all (pure branding banner) without schema changes.
    link_type = Column(String(20), nullable=True)  # poi, trip, external, none
    link_target = Column(String(500), nullable=True)  # POI/Trip UUID as string, or URL
    priority = Column(Integer, default=0, index=True)  # higher shows first
    starts_at = Column(DateTime, nullable=True)
    ends_at = Column(DateTime, nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

    tenant = relationship("Tenant", back_populates="promotions")


class Trip(Base):
    __tablename__ = "trips"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    num_days = Column(Integer, default=1)
    budget_level = Column(String(20), default="medium")  # low, medium, high
    budget_currency = Column(String(10))  # set from tenant by trip generation; never hardcoded
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
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

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
    currency = Column(String(10))  # set from tenant by the booking endpoint; never hardcoded
    booking_data = Column(JSON, default=dict)
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

    tenant = relationship("Tenant", back_populates="bookings")
    user = relationship("User", back_populates="bookings")
    poi = relationship("POI", back_populates="bookings")


class Review(Base):
    __tablename__ = "reviews"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    poi_id = Column(UUID(as_uuid=True), ForeignKey("pois.id"), nullable=False, index=True)
    rating = Column(Integer, nullable=False, index=True)  # From 1 to 5
    comment = Column(Text, nullable=True)
    created_at = Column(DateTime, default=utcnow, index=True)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

    tenant = relationship("Tenant", back_populates="reviews")
    user = relationship("User", back_populates="reviews")
    poi = relationship("POI", back_populates="reviews")

    __table_args__ = (
        UniqueConstraint("tenant_id", "user_id", "poi_id", name="uq_review_tenant_user_poi"),
    )


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
    created_at = Column(DateTime, default=utcnow)

    tenant = relationship("Tenant", back_populates="analytics_events")
    user = relationship("User", back_populates="analytics_events")


class ChatMessage(Base):
    __tablename__ = "chat_messages"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    role = Column(String(20), nullable=False)  # user, assistant, system
    content = Column(Text, nullable=False)
    context = Column(JSON, default=dict)
    created_at = Column(DateTime, default=utcnow)

    tenant = relationship("Tenant", back_populates="chat_messages")
    user = relationship("User", back_populates="chat_messages")

# Features dont le modèle est choisi par le tenant. « embeddings » est volontairement
# absent : le modèle d'embedding est fixé au niveau plateforme (pgvector = dimension fixe).
TENANT_CONFIGURABLE_FEATURES = ("chat", "research", "recommendation", "translation")


class TenantAIConfig(Base):
    """Configuration IA d'un tenant : provider, modèles par feature, limites.
    Les secrets (clés API BYOK) sont dans TenantAICredential, jamais ici."""
    __tablename__ = "tenant_ai_configs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    primary_provider = Column(String(32), nullable=False, default="openai")
    fallback_provider = Column(String(32), nullable=True)   # stocké, pas encore utilisé
    models = Column(JSON, nullable=False, default=dict)     # {"chat": "...", "research": "..."}
    default_params = Column(JSON, nullable=False, default=dict)  # {"temperature": 0.7, "max_tokens": 1024}
    enabled_features = Column(ARRAY(String), nullable=False, default=lambda: ["chat", "recommendation"])
    monthly_spend_limit_usd = Column(Numeric(10, 4), nullable=True)  # None = pas de plafond
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

    tenant = relationship("Tenant")

    @validates("models")
    def _validate_models(self, _key, value):
        value = value or {}
        unknown = set(value) - set(TENANT_CONFIGURABLE_FEATURES)
        if unknown:
            raise ValueError(
                f"Features non configurables par tenant : {sorted(unknown)} "
                f"(autorisées : {list(TENANT_CONFIGURABLE_FEATURES)})"
            )
        return value


class TenantAICredential(Base):
    """Clé API BYOK d'un tenant pour un provider, chiffrée (AES-256-GCM, AAD tenant+provider).
    Une ligne par (tenant, provider) : prépare le fallback avec des credentials distincts."""
    __tablename__ = "tenant_ai_credentials"
    __table_args__ = (UniqueConstraint("tenant_id", "provider", name="uq_tenant_ai_credential"),)

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False,
    )
    provider = Column(String(32), nullable=False)
    encrypted_key = Column(Text, nullable=False)   # jeton produit par CredentialCrypto
    key_version = Column(Integer, nullable=False)  # version de la clé maître utilisée
    key_last4 = Column(String(4), nullable=False)  # affichage UI uniquement
    created_at = Column(DateTime, default=utcnow)
    rotated_at = Column(DateTime, nullable=True)

    tenant = relationship("Tenant")
QUOTA_METRICS = ("usd_cost", "credits", "tokens")
AI_CALL_STATUSES = (
    "success", "invalid_api_key", "permission_denied", "model_unavailable",
    "quota_exceeded", "rate_limited", "network_error", "timeout",
    "cancelled", "provider_error", "unknown_error",
)  # aligné sur les catégories déjà renvoyées par _run_health_check


class TenantAIQuotaConfig(Base):
    """Quota mensuel IA d'un tenant : limite, consommation courante, comportement au seuil.
    current_period_usage est un compteur dénormalisé (source de vérité = TenantAIUsageLog)."""
    __tablename__ = "tenant_ai_quota_configs"

    tenant_id = Column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        primary_key=True,
    )
    quota_metric = Column(String(16), nullable=False, default="usd_cost")
    monthly_limit = Column(Numeric(12, 4), nullable=False, default=50)
    current_period_usage = Column(Numeric(12, 4), nullable=False, default=0)
    soft_limit_threshold_pct = Column(Integer, nullable=False, default=80)
    soft_limit_alert_sent = Column(Boolean, nullable=False, default=False)
    hard_limit_enforced = Column(Boolean, nullable=False, default=True)
    billing_cycle_anchor_day = Column(Integer, nullable=False, default=1)
    current_period_start = Column(DateTime, default=utcnow)
    current_period_end = Column(DateTime, nullable=False)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

    tenant = relationship("Tenant")

    @validates("quota_metric")
    def _validate_quota_metric(self, _key, value):
        if value not in QUOTA_METRICS:
            raise ValueError(f"quota_metric invalide : {value!r} (autorisés : {QUOTA_METRICS})")
        return value

    @validates("soft_limit_threshold_pct")
    def _validate_threshold(self, _key, value):
        if not (1 <= value <= 100):
            raise ValueError("soft_limit_threshold_pct doit être entre 1 et 100")
        return value

    @validates("billing_cycle_anchor_day")
    def _validate_anchor_day(self, _key, value):
        if not (1 <= value <= 28):
            raise ValueError("billing_cycle_anchor_day doit être entre 1 et 28")
        return value


class TenantAIUsageLog(Base):
    """Journal d'usage IA, append-only : une ligne par appel provider effectif.
    Source de vérité pour l'audit/facturation ; TenantAIQuotaConfig.current_period_usage
    n'est qu'un cache incrémenté dans la même transaction que l'insert ici."""
    __tablename__ = "tenant_ai_usage_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id = Column(UUID(as_uuid=True), nullable=True)  # NULL = appel système
    request_id = Column(UUID(as_uuid=True), nullable=True)  # corrèle plusieurs appels d'une requête logique

    provider = Column(String(32), nullable=False)
    model = Column(String(150), nullable=False)
    feature = Column(String(64), nullable=False)  # 'chat', 'rag_ingestion', 'cv_extract', ...

    prompt_tokens = Column(Integer, nullable=False, default=0)
    completion_tokens = Column(Integer, nullable=False, default=0)
    cached_tokens = Column(Integer, nullable=False, default=0)

    estimated_cost_usd = Column(Numeric(12, 6), nullable=False, default=0)
    pricing_snapshot = Column(JSON, nullable=False, default=dict)  # tarif appliqué au moment de l'appel

    status = Column(String(24), nullable=False, default="success")
    error_code = Column(String(100), nullable=True)  # catégorie stable uniquement, jamais le texte brut provider
    latency_ms = Column(Integer, nullable=True)

    created_at = Column(DateTime, default=utcnow)

    tenant = relationship("Tenant")

    @validates("status")
    def _validate_status(self, _key, value):
        if value not in AI_CALL_STATUSES:
            raise ValueError(f"status invalide : {value!r} (autorisés : {AI_CALL_STATUSES})")
        return value

    @property
    def total_tokens(self):
        return self.prompt_tokens + self.completion_tokens