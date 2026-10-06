# Algeria Market Pack

**Layer:** research policy, market-specific knowledge (normative where marked).
**Rule prefix:** `ALG`. Conventions are defined in `SKILL.md` §0.

Algeria is a first-class reference context for Discover AI, but the research
engine is international. This file is **market knowledge**, not core logic.

## ALG-00 — Modularity (MUST)

- Algeria-specific rules MUST NOT be turned into country branches in code (`if country == "DZ"`). That would violate the repository's principle 1 (see `SKILL.md` §5).
- Market knowledge belongs in **data and configuration** (for example per-country research source configuration), and in this file as guidance for the researcher.
- A different market gets its own `<country>-pitfalls.md` of the same shape. Nothing in the global files may assume Algeria.

## ALG-01 — Preferred authorities by claim (Algeria)

Apply SRC-01. Candidates, depending on the claim: ministries, the Journal Officiel (JORA), wilayas, communes, national agencies, national museums, public cultural institutions, tourism authorities, heritage institutions, sports federations, universities, CRASC, CNRPAH.

## ALG-02 — Pitfalls

- **ALG-02a** For legal claims JORA MUST be preferred over press summaries. JORA documents MAY need OCR (see WFL-08, PRV-05).
- **ALG-02b** Arabic and French official versions MAY diverge. If they materially conflict, the conflict MUST be preserved until resolved (PRV-09).
- **ALG-02c** Wilaya and commune sites vary widely in freshness. Their pages MUST NOT be assumed current (FRS-02).
- **ALG-02d** Ministry and agency URLs move. A dead official URL MUST be recorded as an access failure (WFL-09), and the researcher SHOULD look for the relocated page before downgrading.
- **ALG-02e** Some institutions publish mainly on Facebook. Official social accounts MAY then be the primary operational source (SRC-06), cross-linked where practical.
- **ALG-02f** Search in Arabic and French, and in English where useful (ENT-04). Keep original names and translations separately.

## ALG-03 — Known official entry points (discovery leads)

These are leads for source discovery, recorded as of 2026-10. They MAY move.
Being on this list does **not** make a page authoritative for a given claim
(SRC-01) and does not skip source identity checks (SRC-03).

- Ministry of Tourism: `mta.gov.dz`; directory of wilaya directorates: `mta.gov.dz/annuaire/?lang=fr` (wilaya sites of the form `<wilaya>.mta.gov.dz`)
- National Tourism Office (ONT): `ont.dz` (destination and booking pages)
- ONAT: `onat.dz`

Where the repository has a per-country research source configuration, these
entries SHOULD be maintained there as data rather than hard-coded in code
(see `SKILL.md` §5).
