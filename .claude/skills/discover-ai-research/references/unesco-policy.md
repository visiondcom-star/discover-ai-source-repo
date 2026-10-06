# UNESCO and Heritage Policy

**Layer:** research policy (normative). **Rule prefix:** `UNE`.
Conventions are defined in `SKILL.md` §0. Generic authority rules live in
`source-policy.md` (SRC-01); this file only adds what is specific to heritage.

Apply each authority **only to the claims it owns**. Do not mechanically
require UNESCO + advisory body + national source for a trivial logistics
claim (opening hours, ticket price): those belong to the site operator
(SRC-01).

---

## UNE-01 — Who owns which heritage claim

| Body / program | Authoritative for | NOT authoritative for |
|---|---|---|
| UNESCO World Heritage Centre | Inscription status, category, criteria, reference number, inscription year, danger status, official boundaries | Visitor logistics, local schedules |
| UNESCO Intangible Cultural Heritage authority | Inscription, list type, communities, safeguarding programs | Treating an element as a physical place |
| UNESCO Memory of the World | Documentary heritage inscription (separate program) | World Heritage or ICH status |
| ICOMOS | Technical evaluation of cultural properties | Final inscription decision |
| IUCN | Technical evaluation of natural and mixed properties | Final inscription decision |
| ICCROM | Conservation and restoration guidance | Inscription status |
| ALECSO / African World Heritage Fund | Regional programs and coordination | Global inscription status |
| CRASC / CNRPAH (Algeria) | Their respective research domains | Institutional schedules, tourism logistics (unless they operate the site) |
| National or local heritage authority | National/local protection status, local facts | UNESCO status |

## UNE-02 — Rules

- **UNE-02a** The Tentative List MUST NOT be reported as an inscription.
- **UNE-02b** Tangible, intangible and documentary heritage MUST be kept distinct. An ICH element MUST NOT be treated as a place unless a competent source ties it to one.
- **UNE-02c** ICOMOS and IUCN evaluations MUST NOT be presented as the inscription decision.
- **UNE-02d** ICCROM MUST be used for conservation claims only.
- **UNE-02e** ALECSO and AWHF MUST be used for regional scope only, and MUST NOT substitute for UNESCO on global status.
- **UNE-02f** A neighboring site, buffer zone or similarly named property MUST NOT be confused with the inscribed property. When inscription covers a serial or multi-component property, the claim MUST name the component.
- **UNE-02g** Separate heritage claims (UNESCO status, advisory evaluation, national protection, research interpretation) MUST be stored as **separate claims with separate provenance**. They MUST NOT be merged into one undifferentiated claim.

## UNE-03 — Heritage workflow

```text
UNESCO status
   + advisory body (where relevant)
   + national / local authority
   + research institution (where relevant)
        ↓
separate claims, each with its own provenance
```

## UNE-04 — Heritage gate (used by the SKILL.md quality gate)

When a task involves heritage, all of UNE-02a … UNE-02g MUST be satisfied, and
UNESCO status MUST have been checked against the relevant UNESCO authority page
that was actually retrieved (WFL-06).
