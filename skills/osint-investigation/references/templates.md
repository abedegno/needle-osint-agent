# Record templates

## Entity (`dossier/entities/<id>.md`)
```yaml
---
id: kebab-case-id
type: company
names: ["Legal Name", "Trading Name"]
jurisdiction: AU            # ISO country code
identifiers: { ACN: "", ABN: "", KvK: "", CRN: "" }
status: unknown             # active | dissolved | unknown
addresses: []
brands: []
linked_entities: []
confidence: C
sources: []
---
## Summary
Narrative.

## Open questions / leads
- 
```

## Person (`dossier/people/<id>.md`)
```yaml
---
id: kebab-case-id
type: person
names: ["Full Name", "Known aliases"]
roles: []                  # e.g. ["director_of: example-trading-ltd"]
nationality: unknown
identifiers: {}
linked_entities: []
confidence: C
sources: []
---
## Summary

## Open questions / leads
- 
```

## Finding (`dossier/findings/<slug>.md`)
```yaml
---
id: finding-slug
title: "Short claim"
entities: []
confidence: C
sources: []
status: open               # open | corroborated | disproven
---
## Fact (sourced)

## Inference (analyst reasoning)

## Corrections
- 
```

## Relationship edge (append to `dossier/relationships.yaml`)
```yaml
- from: entity-or-person-id
  to: entity-or-person-id
  type: shared_address       # see SKILL vocabulary
  confidence: C
  note: ""
  sources: []
```

## Source (append to `dossier/sources/register.yaml`)
```yaml
- id: src-NNN
  title: ""
  type: web                 # web | primary_document | registry | press | court
  origin: ""
  url: ""
  archive_url: ""           # Wayback / crawl4ai snapshot path
  retrieved: YYYY-MM-DD
  sha256: ""
  sift_verdict: ""
```
