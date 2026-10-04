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
RESEARCH_TRIGGER_TYPES = (
    "tenant_created",
    "scheduled",
    "manual_refresh",
    "admin_replay",
    "collection",
)

# research_jobs.status lifecycle.
RESEARCH_JOB_STATUSES = ("pending", "processing", "done", "failed")

# Manual refresh rate-limit: at most one manual_refresh trigger per tenant
# in this rolling window, enforced in the research/run endpoint.
RESEARCH_MANUAL_REFRESH_COOLDOWN_DAYS = 30

# Collection rate-limit: at most one collection run per tenant in this rolling
# window, whatever the previous run's final status, enforced in the
# research/collection/run endpoint. A collection costs no LLM quota: this only
# protects the Wikimedia servers, so the window is far shorter than the
# manual-refresh cooldown.
RESEARCH_COLLECTION_COOLDOWN_MINUTES = 10

# research_collection_jobs.status lifecycle.
RESEARCH_COLLECTION_JOB_STATUSES = ("pending", "processing", "done", "failed")

# Transitions autorisées pour tenant_categories.status.
#
# `rejected` est terminal : pas de « resurrect » d'une catégorie que l'admin a
# écartée (sinon un clic passé l'invaliderait sans trace). Aucune
# auto-transition non plus : passer active → active ne sert à rien et masquerait
# une erreur de clic. La létalité de la décision est voulue (Principe 5 :
# l'IA propose, l'humain tranche).
CATEGORY_TRANSITIONS = {
    "proposed": frozenset({"active", "rejected"}),
    "active": frozenset({"rejected"}),
    "rejected": frozenset(),
}

