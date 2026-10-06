# Provenance, Validation and Trust Policy

**Layer:** research policy (normative). **Rule prefix:** `PRV`.
Conventions are defined in `SKILL.md` §0. Data shapes are in `output-schema.md`
(conceptual only); this file owns the **meaning** of every controlled
vocabulary and the rules for assigning them.

This file is the single home of: the provenance chain, evidence rules, claim
status, confidence, content origin, conflict resolution, sensitivity, media
provenance, and eligibility for trusted RAG.

---

## PRV-01 — Provenance chain

Knowledge MUST follow:

```text
Source → Evidence → Claim → Validation → Knowledge Record → RAG
```

The minimum provenance graph is `Entity ← Claim ← Evidence ← Source`, with
temporal (FRS-01) and validation metadata attached to the claim. Identifiers
(`research_id`, `entity_id`, `source_id`, `evidence_id`, `claim_id`,
`knowledge_id`, `offer_id`) SHOULD stay stable wherever the backend persists
records.

## PRV-02 — Evidence rules

Evidence is not a claim.

- Evidence MUST stay close to the source wording and preserve the context needed to interpret it.
- Source text MUST NOT be silently corrected.
- Page numbers, sections and quotations MUST NOT be invented.
- Information MUST NOT be attributed to a source that does not support it.
- Evidence SHOULD carry: source id, document title, page / section, short excerpt, language, extraction method, extraction quality.

## PRV-03 — Claim atomicity

- A claim SHOULD be atomic: one assertion about one entity ("Museum X opens at 09:00", "Museum X is closed on Monday" — not one compound claim).
- Several sources MUST NOT be merged into one compound claim attributed to only one of them.
- Institutional interpretation MUST NOT be turned into universal fact.

## PRV-04 — Claim status vocabulary

| Status | Meaning |
|---|---|
| `VERIFIED` | A competent authoritative source directly supports the claim |
| `CORROBORATED` | Several sufficiently independent reliable sources support the claim (SRC-05) |
| `PARTIALLY_VERIFIED` | Some components are supported, the whole claim is not |
| `CONFLICTING` | Credible current sources materially disagree |
| `OUTDATED` | The information was authentic but is no longer current |
| `UNVERIFIED` | A claim exists but sufficient evidence was not established |
| `NOT_FOUND` | Reasonable research found no reliable supporting evidence |
| `CONTESTED` | The factual basis or interpretation is disputed among credible sources |

`CONTESTED` MUST NOT be converted to `VERIFIED` merely because one institution states one position.

## PRV-05 — Extraction quality, OCR and tables

- Any evidence derived from OCR MUST record `extraction_method = OCR` and an `ocr_confidence` from the PRV-07 vocabulary.
- For an important value, the page image SHOULD be checked when OCR is ambiguous.
- For tables, column meaning, units, dates, footnotes and row/column relationships MUST be preserved.
- Table values MUST NOT be invented or "completed".
- Poor extraction quality MUST lower confidence (PRV-07).

## PRV-06 — Assigning a status

- `VERIFIED` requires: resolved source identity (SRC-03), resolved entity (ENT-01), authority appropriate to the claim (SRC-01), and evidence that actually supports the claim (PRV-02).
- `CORROBORATED` additionally requires independence (SRC-05).
- If evidence is missing, the status MUST be `UNVERIFIED` or `NOT_FOUND`. Plausibility MUST NOT substitute for evidence.
- A claim whose supporting evidence is no longer current becomes `OUTDATED` (FRS-03), not deleted.

## PRV-07 — Confidence vocabulary

Values: `VERY_HIGH`, `HIGH`, `MEDIUM`, `LOW`, `UNKNOWN`.

- Confidence reflects **evidence quality**, not plausibility.
- It SHOULD consider: claim-appropriate authority, directness, source independence, freshness, extraction quality, corroboration, contradiction, entity resolution confidence.
- An implementation MAY compute an internal numeric score, but the vocabulary above remains the human-facing contract. Numeric thresholds are an implementation matter and are NOT defined here (see `SKILL.md` §5).

## PRV-08 — Content origin

Every knowledge item SHOULD record its origin: `human`, `ai_assisted`, `ai_generated`, `unknown`.

- AI-generated content MUST NOT silently become an authoritative source.
- AI MAY help to summarize, translate, normalize, classify and extract candidate claims. Its output does not become evidence by being produced by an AI.

## PRV-09 — Conflict resolution

When sources conflict, in order:

1. Confirm they concern the same entity (ENT-01).
2. Check independence (SRC-05) and whether one copied the other.
3. Compare publication and update dates.
4. Compare claim-specific authority (SRC-01).
5. Prefer the competent primary source where justified.
6. Prefer the newer valid source when authority is comparable.
7. If unresolved, mark `CONFLICTING`.

Rules:

- Credible conflicts MUST NOT be silently resolved, and consensus MUST NOT be manufactured.
- All materially relevant versions MUST be preserved.
- Example: official museum says 09:00–17:00, old tourism article says 10:00–18:00 → current claim `VERIFIED`, old claim `OUTDATED`. Two current authoritative sources disagree → `CONFLICTING`.
- If Arabic and French official texts materially conflict, the conflict MUST be preserved until resolved.

## PRV-10 — Field-level provenance

Provenance SHOULD be attachable to individual fields (name, hours, UNESCO status…) rather than only to a whole document. This is the preferred long-term direction.

- A new persistence model MUST NOT be introduced merely to implement this. The existing repository MUST be inspected first (`SKILL.md` CC-02).

## PRV-11 — Fact versus recommendation

- The **factual layer** (name, location, category, official status, hours, price, facilities, accessibility, official description) MUST be kept separate from the **recommendation layer** (relevance, seasonality, family suitability, popularity, thematic fit).
- A recommendation score is NOT an evidence-authority score, and an AI-generated score MUST NOT masquerade as an official fact.

## PRV-12 — Historical and cultural sensitivity

For identity, heritage, ownership, historical interpretation and contested narratives:

- Evidence MUST be distinguished from interpretation, and the party making a claim MUST be identified.
- Institutional attribution MUST be preserved. Academic interpretation MUST be distinguished from an official position.
- Independent corroboration SHOULD be sought where practical.
- Unresolved disputes MUST be marked (`CONTESTED`). Disputed narratives MUST NOT be presented as settled.
- The objective is evidence fidelity, not artificial neutrality.

## PRV-13 — Media and image provenance

When media is part of a knowledge record, it SHOULD preserve: media type, source URL, source id, creator/organization, published-at, retrieved-at, license / usage information, caption.

- Media MUST be classified: `official`, `licensed_third_party`, `user_generated`, `illustrative`, `ai_generated`, `unknown`.
- Factual identity, location, date or ownership MUST NOT be inferred from an image alone when a textual authoritative source is available.
- Image licensing is separate from factual verification and MUST be assessed separately for commercial use.

## PRV-14 — Eligibility for trusted RAG

A trusted knowledge item requires **all** of: source identity established, entity resolved, evidence extracted, claim identified, status assigned, confidence assigned, temporal state understood, provenance retained, acceptable extraction quality.

- Raw search results MUST NOT be ingested into trusted RAG.
- The following MUST NOT be ingested as trusted fact: `NOT_FOUND`, `UNVERIFIED`, unresolved source identity, unsupported claims, expired information without temporal labeling, AI-generated material not explicitly reviewed and flagged.
- `CONFLICTING` and `CONTESTED` claims MAY be stored for audit but MUST remain flagged.
- Superseded claims MUST be marked `OUTDATED` and MAY be retained for audit.
- Provenance and traceability MUST survive every transformation (summarizing, chunking, embedding).
- Retrieval isolation (per tenant) is an implementation concern defined by the repository (`SKILL.md` §5), not redefined here.
