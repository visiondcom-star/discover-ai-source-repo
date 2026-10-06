# Source Policy

**Layer:** research policy (normative). **Rule prefix:** `SRC`.
Conventions (MUST / SHOULD / MAY / MUST NOT, rule IDs) are defined in `SKILL.md` §0.

This file is the single home of: claim-dependent authority, source tiers,
source identity, URL canonicalization, source independence, official social
accounts, and sports authority.

---

## SRC-01 — Authority is claim-dependent

- Authority MUST be decided by **who is competent to establish the specific claim**.
- A source MAY be authoritative for one claim and non-authoritative for another.
- Domain suffix (`.gov`, `.dz`, `.com`) and search ranking MUST NOT be used as proof of authority or of unreliability.

| Claim | Preferred authority |
|---|---|
| National policy | Competent ministry / national authority |
| Regulation, legal text | Competent government authority; official gazette (see `algeria-pitfalls.md` for JORA) |
| Museum hours, collection | The museum / official institution |
| UNESCO inscription | UNESCO authority (see `unesco-policy.md`) |
| Local heritage protection | Competent national or local authority |
| Festival program, dates | Official organizer |
| Sports fixture / result | See SRC-07 |
| Club information | Official club |
| Hotel availability and amenities | The hotel / authorized booking source |
| Restaurant menu | The restaurant |
| Transport timetable | Transport operator |
| Academic interpretation | University / research institution |
| Current local announcement | Official institutional account (see SRC-06) |

## SRC-02 — Source tiers

Tiers rank a source's general standing. They never replace SRC-01.

| Tier | Meaning | Examples |
|---|---|---|
| 1 | Primary authoritative source (claim-dependent) | Ministries, government portals, official gazettes, national agencies, wilayas and communes, national tourism and heritage authorities, public museums, universities and research institutions, sports federations, official event organizers, UNESCO, ICOMOS, IUCN, ICCROM, ALECSO, AWHF, CRASC, CNRPAH |
| 2 | Official entity source | Official museum / hotel / restaurant / operator / club / festival / venue website; clearly controlled official social account |
| 3 | Recognized specialist organization | Professional organizations, cultural and tourism associations, academic institutions, professional federations |
| 4 | Reliable secondary source | Established newspapers, specialist tourism and cultural publications, reputable sports media. Context and corroboration only |
| 5 | Discovery-only | Generic blogs, aggregators, forums, anonymous pages, unsourced directories, user-generated listings |

- Tier 1 MUST NOT be read as "authoritative for everything".
- Tier 5 sources MAY be used to find leads. They MUST NOT be the final authority for an important claim without independent verification.

## SRC-03 — Source identity

- A source that supports an important claim MUST have its identity resolved first: organization, domain, institutional links, consistency with the entity, page context. For official social accounts, cross-links (see SRC-06).
- The following MUST NOT be invented: URL, organization, source title, publication date, update date, verification status, account ownership.
- If identity cannot be established, the source MUST NOT support a `VERIFIED` claim (see `provenance-policy.md`).

## SRC-04 — URL canonicalization

- Equivalent URLs (scheme, `www`, trailing slash, tracking parameters, mirror paths) SHOULD be normalized before counting sources as distinct.
- The canonical URL and the retrieved URL SHOULD both be kept when they differ.

## SRC-05 — Independence and deduplication

Corroboration requires independence.

- Pages MUST NOT be counted as independent evidence when they: reproduce the same press release, quote the same source, copy the same database, republish identical text, share the same parent organization, or are translations of the same source.
- Such pages form **one evidence lineage**.
- A claim MAY be marked `CORROBORATED` only when supporting evidence is sufficiently independent or comes from multiple competent authorities.
- When independence cannot be determined, it MUST be recorded as `UNKNOWN`. It MUST NOT be assumed.
- Dependent sources MUST NOT raise confidence on their own (see `provenance-policy.md`).

## SRC-06 — Official social accounts

Official social accounts MAY be primary evidence for temporary closures, event announcements, program changes, emergency information and current institutional announcements.

- Each social claim MUST record: platform, account name, account URL, post URL, post date, retrieved-at, officiality signal, source id.
- Ownership SHOULD be verified through an official cross-link (official site links to the account, or the account links to the official site). A verification badge alone is NOT sufficient.
- Reposts are weaker than originals. Screenshots are weaker than the original post.
- Posts can be edited or deleted: an archive SHOULD be preserved when available.
- A social post does not automatically override a formal document. A **newer** official operational announcement MAY establish current operational status (hours, closure) when it comes from the competent entity.

## SRC-07 — Sports authority chain

Preferred order: international federation → national federation → official club → official competition organizer → reliable specialist sports source.

- For current schedules, results, standings and fixtures, the most recent official competition source MUST be used.
- A current result MUST NOT be inferred from an old article (see `freshness-policy.md`).

## SRC-08 — Third-party commercial listings

A third-party listing (aggregator, marketplace, review site) MUST NOT by itself establish that an offer, price or availability is currently valid. Validity rules: `freshness-policy.md` FRS-06.
