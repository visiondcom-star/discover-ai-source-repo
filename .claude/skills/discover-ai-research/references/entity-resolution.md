# Entity Resolution, Language and Location

**Layer:** research policy (normative). **Rule prefix:** `ENT`.
Conventions are defined in `SKILL.md` §0.

This file is the single home of: entity resolution, aliases and translations,
multilingual research, and geographic provenance.

---

## ENT-01 — Resolve before attaching claims

Before attaching any claim to an entity, the researcher MUST determine whether the references describe the same real-world entity. Material ambiguity MUST be resolved, or surfaced as a limitation, before strong claims are made.

## ENT-02 — Evidence for identity

Resolution SHOULD rely on contextual evidence: address, coordinates, official domain, organization, telephone, institutional identity, historical identity.

- Entities MUST NOT be merged solely because their names look similar.
- Similarly named places MUST NOT be assumed to share a location.
- `resolution_confidence` SHOULD be recorded using the confidence vocabulary of PRV-07.

## ENT-03 — Names, aliases, translations

An entity may have an Arabic name, French name, English name, transliteration, historical name, abbreviation, spelling variants and local names.

- The original **official** name MUST be preserved as the canonical name.
- Aliases and translations MUST be stored separately from the canonical name.
- Translations MUST NOT be treated as independent entities, nor as independent sources (SRC-05).

## ENT-04 — Multilingual research

- The researcher SHOULD search in the original language of the authoritative institution and in other relevant languages (for example Arabic, French, English).
- Translation MUST be clearly distinguished from source text.
- Original wording MUST be preserved for sensitive historical or cultural claims (PRV-12).

## ENT-05 — Geographic provenance

For place-based knowledge, location SHOULD be kept as structured data with its own provenance: country, region, city, address, latitude, longitude, location source, location confidence.

- Coordinates MUST NOT be invented.
- An exact address MUST NOT be inferred from a vague locality.
- Administrative location and physical location MUST be distinguished.
- The source supporting an important geographic fact MUST be preserved.
