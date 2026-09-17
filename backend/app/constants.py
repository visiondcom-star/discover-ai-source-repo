"""Domain-wide shared constants — single source of truth.

PARENT_FAMILIES feeds three consumers that must never drift apart:
- the LLM extraction prompt (Niveau 1 mapping is a closed enum),
- the Pydantic validation pattern on category proposals,
- the admin UI filter options.

Order matters: it is the display order of the macro-families.
"""

# Niveau 1 macro-families — the fixed taxonomy every tenant shares.
# Level 2 (tenant_categories.slug) is tenant-specific and AI-generated,
# but its parent must always be one of these values (seeded in
# initial_data.py; add here FIRST, seed second).
PARENT_FAMILIES = (
    "culture",
    "history",
    "nature",
    "desert",
    "adventure",
    "food",
    "beaches",
    "wellness",
)

# tenant_categories.status lifecycle.
CATEGORY_STATUSES = ("proposed", "active", "rejected")

# destination_research_documents.source_type — where a research document
# came from. 'autre' is the catch-all so the ingest never rejects a
# collectible source for lack of a better bucket.
RESEARCH_SOURCE_TYPES = ("guide", "office_tourisme", "wiki", "autre")

# destination_research_documents.status lifecycle.
RESEARCH_DOCUMENT_STATUSES = ("raw", "processed", "discarded")

# research_jobs.trigger_type — how a run was started.
RESEARCH_TRIGGER_TYPES = ("tenant_created", "scheduled", "manual_refresh", "admin_replay")

# research_jobs.status lifecycle.
RESEARCH_JOB_STATUSES = ("pending", "processing", "done", "failed")

# Manual refresh rate-limit: at most one manual_refresh trigger per tenant
# in this rolling window, enforced in the research/run endpoint.
RESEARCH_MANUAL_REFRESH_COOLDOWN_DAYS = 30
