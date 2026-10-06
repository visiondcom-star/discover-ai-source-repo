# Freshness, Temporal Validity and Offers

**Layer:** research policy (normative). **Rule prefix:** `FRS`.
Conventions are defined in `SKILL.md` §0.

This file is the single home of: temporal fields, freshness classes, volatility,
commercial offer validity, and change detection.

---

## FRS-01 — Temporal fields

Research output MUST distinguish:

| Field | Meaning |
|---|---|
| `published_at` | When the source was published |
| `updated_at` | When the source says it was last updated |
| `retrieved_at` | When Claude actually retrieved it |
| `last_verified_at` | When the claim was last validated against evidence |
| `valid_from` / `valid_until` | The period during which the claimed fact holds |
| `temporal_status` | Freshness class (FRS-03) |

Unknown dates MUST be left empty, never guessed (SKILL.md SKL-03).

## FRS-02 — Old pages are not current

An old page MUST NOT be treated as current merely because it is still online. A current result MUST NOT be inferred from an old article.

## FRS-03 — Freshness classes

`CURRENT`, `RECENT`, `STALE`, `OUTDATED`, `UNKNOWN`.

Each claim whose truth can change over time MUST receive one. When it cannot be determined, the class is `UNKNOWN`.

## FRS-04 — Volatility

| Volatility | Examples | Revalidation pressure |
|---|---|---|
| High | Prices, opening hours, transport, event dates, availability, temporary closures, current offers, regulations, contact details | Recheck aggressively |
| Moderate | Services, facilities, hotel amenities, restaurant offerings, tourism programs | Recheck periodically |
| Low | Historical background, architecture, institutional history, established heritage facts | Lower pressure |

## FRS-05 — TTL is not a research decision

Actual TTL / revalidation intervals MUST be defined by product and backend requirements. A research response MUST NOT invent them.

## FRS-06 — Commercial and tourism offers

Offers, promotions, prices, packages, availability and booking information are time-sensitive data.

- An expired offer MUST NOT be presented as active.
- A price or availability MUST NOT be invented.
- Published price MUST be distinguished from confirmed availability.
- Currency and pricing conditions MUST be preserved.
- A booking / source URL MUST be recorded only when actually verified.
- A third-party listing does not prove an offer is active (SRC-08).
- An offer SHOULD carry its **own** validity state rather than inheriting the provider's general status.

Offer checklist used by the quality gate: validity period checked; price and currency verified; availability distinguished from published offer; booking/source URL verified; expired offers not shown as active.

## FRS-07 — Change detection

Change detection MAY be used for important sources when justified:

```text
Retrieve → normalize relevant content → fingerprint → compare with previous version
   unchanged → keep state
   changed   → identify affected claims → revalidate those claims
```

- A changed page does not imply every claim changed. Only affected claims SHOULD be revalidated.
- Change detection is a Phase 3 capability (`SKILL.md` CC-07). It MUST NOT be built unless asked.

## FRS-08 — Temporal labeling

Current and historical information MUST NOT be mixed without temporal labels. Expired or superseded information that is retained MUST stay distinguishable (PRV-14).
