# Entities

One file per company or organisation. The filename (minus `.md`) is the entity's
canonical id: kebab-case, human-readable, and **permanent once created** — other
files reference it (`linked_entities`, a finding's `entities:` list, relationship
edges), so never rename a slug once anything else cites it.

Keep an `_index.md` (a table of every entity — name, jurisdiction, confidence,
status) up to date as you add entities, so a reader can find the roster without
opening every file.

## Frontmatter

```yaml
---
id: kebab-case-id
type: company
names: ["Legal Name", "Trading Name"]
jurisdiction: XX              # ISO country code
identifiers: {}                # registry numbers, e.g. { CRN: "12345678" }
status: unknown                 # active | dissolved | unknown
addresses: []
brands: []
linked_entities: []             # ids of related entities/people
confidence: C                   # A | B | C | D — see the confidence scale in README.md
sources: []                     # src-<ULID> ids
---
## Summary
Narrative. Every claim cited inline, e.g. [src-01ARZ3NDEKTSV4RRFFQ69G5FAW].

## Open questions / leads
-
```

## Example (synthetic)

`entities/example-trading-ltd.md`:

```yaml
---
id: example-trading-ltd
type: company
names: ["Example Trading Ltd"]
jurisdiction: GB
identifiers: { CRN: "00000001" }
status: "Active [src-01ARZ3NDEKTSV4RRFFQ69G5FAW]"
addresses: ["Registered office: 1 Example Street, London, EC1A 1AA [src-01ARZ3NDEKTSV4RRFFQ69G5FAW]"]
brands: ["ExampleBrand"]
linked_entities: [example-holdings-bv, jane-example]
confidence: B
sources: [src-01ARZ3NDEKTSV4RRFFQ69G5FAW]
---
## Summary
Registered UK company, incorporated 2020, trading as ExampleBrand. The companies
register confirms active status and one listed director, Jane Example
[src-01ARZ3NDEKTSV4RRFFQ69G5FAW] (B — single primary-register source).

## Open questions / leads
- Beneficial ownership beyond the disclosed director — not yet checked.
```
