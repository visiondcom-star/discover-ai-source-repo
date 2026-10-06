# Output Schema (Conceptual)

**Layer:** conceptual data model. **Rule prefix:** `OUT`.
Conventions are defined in `SKILL.md` §0.

> **This is not a database schema.** Shapes below are the *research contract*:
> what a researcher returns and what a knowledge record means. They do not
> authorize migrations, tables or new services. How (and whether) any of this
> is persisted follows the actual repository (`SKILL.md` §5, CC-02, CC-03).
>
> Vocabularies are **defined elsewhere** and only referenced here:
> claim status → PRV-04, confidence → PRV-07, content origin → PRV-08,
> temporal fields and classes → FRS-01 / FRS-03, media classes → PRV-13.

---

## OUT-01 — Rules

- Output MUST NOT contain fabricated empty data. If nothing reliable was found, return an explicit `NOT_FOUND` (PRV-04).
- Unknown values MUST be `null`, never guessed.
- Shapes SHOULD stay backward compatible: add optional fields rather than renaming.

## Research Request

```json
{
  "research_id": "generated-id",
  "query": "original question",
  "subject": "main subject",
  "entity_hint": null,
  "location": { "country": null, "region": null, "city": null,
                "address": null, "latitude": null, "longitude": null },
  "domain": "tourism",
  "claim_types": [],
  "language_preferences": ["ar", "fr", "en"],
  "freshness_requirement": "current",
  "required_evidence": true,
  "output_mode": "research",
  "high_impact": false
}
```

## Source

```json
{
  "source_id": "src_001",
  "organization": "Institution name",
  "name": "Source name",
  "type": "official",
  "tier": 1,
  "domain": "example.org",
  "canonical_url": "https://example.org/page",
  "retrieved_url": null,
  "title": "Official page title",
  "published_at": null,
  "updated_at": null,
  "retrieved_at": "timestamp",
  "language": "fr",
  "independence": "UNKNOWN",
  "access_status": "ok"
}
```

`tier` → SRC-02. `independence` → SRC-05 (`INDEPENDENT | DEPENDENT | UNKNOWN`). `access_status` → WFL-09.

## Entity

```json
{
  "entity_id": "entity_001",
  "canonical_name": "…",
  "aliases": [],
  "entity_type": "museum",
  "country": null, "city": null, "address": null,
  "latitude": null, "longitude": null,
  "location_source_id": null,
  "location_confidence": "UNKNOWN",
  "resolution_confidence": "HIGH"
}
```

→ ENT-01 … ENT-05.

## Evidence

```json
{
  "evidence_id": "ev_001",
  "source_id": "src_001",
  "document_title": "Official document",
  "page": null,
  "section": "Opening hours",
  "excerpt": "Relevant short evidence",
  "language": "fr",
  "extraction_method": "pdf_text",
  "extraction_quality": "HIGH",
  "ocr_confidence": null
}
```

→ PRV-02, PRV-05.

## Claim

```json
{
  "claim_id": "claim_001",
  "entity_id": "entity_001",
  "predicate": "opening_hours",
  "value": "09:00-17:00",
  "status": "VERIFIED",
  "confidence": "HIGH",
  "content_origin": "human",
  "temporal_status": "CURRENT",
  "valid_from": null,
  "valid_until": null,
  "last_verified_at": "2026-10-05T10:00:00Z",
  "evidence_ids": ["ev_001"],
  "source_ids": ["src_001"],
  "conflict_ids": []
}
```

## Knowledge Record

A Claim that passed PRV-14, plus `knowledge_id`. It is the unit eligible for trusted RAG.

```json
{
  "knowledge_id": "knowledge_001",
  "entity_id": "entity_001",
  "claim": { "predicate": "opening_hours", "value": "09:00-17:00" },
  "status": "VERIFIED",
  "confidence": "HIGH",
  "content_origin": "human",
  "temporal_status": "CURRENT",
  "valid_from": null,
  "valid_until": null,
  "last_verified_at": "2026-10-05T10:00:00Z",
  "source_ids": ["src_001"],
  "evidence_ids": ["ev_001"],
  "conflict_ids": []
}
```

## Field-level provenance (direction, PRV-10)

```json
{
  "entity": {
    "canonical_name": { "value": "Museum X", "source_ids": ["src_001"] },
    "opening_hours":  { "value": "09:00-17:00", "source_ids": ["src_002"],
                        "last_verified_at": "2026-10-05" },
    "unesco_status":  { "value": "WORLD_HERITAGE", "source_ids": ["src_003"] }
  }
}
```

## Offer

```json
{
  "offer_id": "offer_001",
  "provider_entity_id": "entity_001",
  "title": "Offer title",
  "price": null, "currency": null,
  "valid_from": null, "valid_until": null,
  "availability": "UNKNOWN",
  "booking_url": null,
  "terms": null,
  "source_id": "src_001",
  "last_verified_at": null,
  "status": "UNKNOWN"
}
```

→ FRS-06.

## Social source fields (SRC-06)

`platform`, `account_name`, `account_url`, `post_url`, `post_date`, `retrieved_at`, `officiality_signal`, `source_id`.

## Media

`media_type`, `source_url`, `source_id`, `creator`, `published_at`, `retrieved_at`, `license`, `caption`, `media_class` → PRV-13.

## Research Manifest (WFL-10)

```json
{
  "research_id": "research_001",
  "query": "…",
  "started_at": "…",
  "completed_at": "…",
  "sources_discovered": 14,
  "sources_used": 6,
  "claims_verified": 11,
  "claims_corroborated": 3,
  "claims_conflicting": 1,
  "claims_unverified": 2,
  "claims_not_found": 1,
  "limitations": []
}
```

## OUT-02 — Output modes

### `research` (human-readable)

Sections, in order: Question · Sources · Findings · Evidence · Conflicts · Freshness · Confidence · Limitations · Conclusion.

### `structured` (machine-readable)

```json
{
  "research": {}, "entities": [], "sources": [], "evidence": [],
  "claims": [], "knowledge_records": [], "conflicts": [], "limitations": []
}
```

### `evidence` (focused package)

Claim · Status · Confidence · Entity · Source · Document · Page / section · Supporting evidence · Validity.
