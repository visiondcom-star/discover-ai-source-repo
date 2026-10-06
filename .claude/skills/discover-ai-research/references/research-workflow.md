# Research Workflow

**Layer:** research policy (normative procedure). **Rule prefix:** `WFL`.
Conventions are defined in `SKILL.md` §0.

This file owns the **order of operations**, retrieval, budget and failure
handling. It does not restate substantive rules: each step points to the rule
that owns it.

---

## WFL-01 — Request normalization

Before searching, the request SHOULD be normalized conceptually into the Research Request shape (`output-schema.md`).

- Missing values MUST NOT be invented.
- Material ambiguity MUST be resolved before strong claims (ENT-01).
- The user's question MUST be kept separate from facts discovered during research.
- The researcher MUST identify whether the information is current, historical, evergreen or time-bounded (FRS-03), and whether the consumer is a human, RAG or an application.

## WFL-02 — Pipeline

```text
 1 Parse            → explicit claims / questions                      (WFL-01)
 2 Resolve entity   → exact place / organization / event               (ENT-01..03)
 3 Discover         → likely primary sources, official documents       (WFL-03)
 4 Prioritize       → rank sources                                     (WFL-03)
 5 Verify identity  → domain, organization, links, consistency         (SRC-03)
 6 Retrieve         → actually fetch the source                        (WFL-06..09)
 7 Extract evidence → only what supports the claim                     (PRV-02, PRV-05)
 8 Extract claims   → atomic claims                                    (PRV-03)
 9 Independence     → detect copies, translations, syndication         (SRC-05)
10 Validate         → authority, directness, independence,
                      freshness, extraction quality, corroboration,
                      contradiction                                    (PRV-04, PRV-06, PRV-07)
11 Resolve conflicts                                                   (PRV-09)
12 Temporal check   → CURRENT / RECENT / STALE / OUTDATED / UNKNOWN    (FRS-01..03)
13 Knowledge records→ only validated, classified claims                (PRV-14)
14 Quality gate                                                        (SKILL.md §7)
15 Output           → requested mode                                   (output-schema.md)
```

Only validated, appropriately classified claims become trusted knowledge (step 13).

## WFL-03 — Discovery and prioritization

- Discovery SHOULD find likely primary sources, official documents, databases, official social accounts, specialist sources and secondary context.
- The researcher MUST NOT stop at the first search result.
- Sources SHOULD be ranked by: authority for the claim (SRC-01), relevance, primary nature, freshness, evidence quality, independence.

## WFL-04 — Search budget

Research SHOULD be staged, not indiscriminate crawling.

| Request | Default budget (independent useful sources) |
|---|---|
| Simple factual request | ≤ 6 |
| High-impact or time-sensitive request | up to 10 |
| Contested or complex research | expand only when justified |

The budget counts independent useful sources, not copied pages (SRC-05).

## WFL-05 — Stop and continue conditions

Stop when:

- one competent, current, unambiguous Tier 1 source directly establishes the claim; **or**
- sufficiently independent reliable sources establish the claim and no authoritative contradiction exists.

Continue when: source identity is uncertain, the claim is high-impact, the information changes rapidly, a credible conflict exists, entity resolution is uncertain, or evidence quality is poor.

## WFL-06 — Retrieval must be real

- Verification MUST be based on a source that was actually retrieved. It MUST NOT be claimed otherwise (SKL-04).
- Preferred retrieval order: API / structured official data → official HTML → official PDF → OCR → official social announcement → reliable secondary source.

## WFL-07 — No silent substitution

An inaccessible primary source MUST NOT be silently replaced by a weaker source. The substitution and the resulting lower confidence MUST be recorded.

## WFL-08 — PDFs, scans, OCR and tables

When an official PDF exists, it SHOULD be preferred.

```text
PDF → publisher / title / date / version → text-quality assessment
    → text extraction → OCR if required → page verification
    → evidence extraction → claim validation
```

OCR and table rules: PRV-05.

## WFL-09 — Access failure handling

If a primary source is unavailable, in order:

1. another official page
2. an official PDF or publication
3. an official institutional account
4. the official parent institution
5. reputable secondary evidence if necessary
6. lower confidence (PRV-07)
7. record the access limitation

Record the failure type when relevant: `403`, dead link, paywall, authentication wall, robots/access limitation, content unavailable.

The researcher MUST NOT bypass authentication or paywalls, invent a substitute URL, or claim that an inaccessible source was checked (SKL-04, SKL-06).

## WFL-10 — Research manifest

A meaningful research operation SHOULD produce a manifest (shape in `output-schema.md`) so that uncertainty and coverage are observable: sources discovered / used, claim counts per status, limitations.
