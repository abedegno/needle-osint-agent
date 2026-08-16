# People

One file per named individual. The filename (minus `.md`) is the person's canonical
id: kebab-case, human-readable, and **permanent once created** — other files
reference it (`linked_entities`, a finding's `entities:` list, relationship edges),
so never rename a slug once anything else cites it.

Records on named individuals are defamation- and PII-sensitive. Use allegation-aware
language throughout: attribute claims to their source, never assert wrongdoing.
Cite every claim; do not republish sensitive personal identifiers (full DOB, home
address, national ID numbers) beyond what is necessary to establish identity and
what the source itself already discloses.

## Frontmatter

```yaml
---
id: kebab-case-id
type: person
names: ["Full Name", "Known aliases"]
roles: []                  # e.g. ["director_of: example-trading-ltd"]
nationality: unknown
identifiers: {}             # e.g. { dob: "1980-01", country_of_residence: "GB" }
linked_entities: []
confidence: C                # A | B | C | D — see the confidence scale in README.md
sources: []                  # src-<ULID> ids
---
## Summary

## Open questions / leads
-
```

## Example (synthetic)

`people/jane-example.md`:

```yaml
---
id: jane-example
type: person
names: ["Jane Example", "Example, Jane"]
roles:
  - "director_of: example-trading-ltd"   # sole listed director, per the companies register (B)
nationality: GB
identifiers: { dob: "1980-01", country_of_residence: "GB" }
linked_entities: [example-trading-ltd]
confidence: B
sources: [src-01ARZ3NDEKTSV4RRFFQ69G5FAW]
---
## Summary
**Sole listed director of Example Trading Ltd.** Jane Example (British, DOB
Jan 1980) is named as the sole director on the companies register extract
[src-01ARZ3NDEKTSV4RRFFQ69G5FAW] (B — single primary-register source).

## Open questions / leads
- Any directorship or ownership role outside Example Trading Ltd — not yet checked.
```
