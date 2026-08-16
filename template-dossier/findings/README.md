# Findings

One file per discrete, graded claim — the atomic unit of evidence in the dossier.
The filename (minus `.md`) is the finding's canonical id: kebab-case, human-readable,
and **permanent once created** — other findings, entities, and people may cite it,
so never rename it.

## Frontmatter

```yaml
---
id: finding-slug              # matches the filename
entities: [entity-slug, ...]   # entities/people this finding concerns
confidence: C                  # A | B | C | D — see the confidence scale in README.md
status: open                   # open | corroborated | disproven
lead: lead-01ARZ...             # the lead-<ULID> that produced this finding
sources: [src-01ARZ..., ...]    # src-<ULID> ids backing the claim
retrieved: 2026-01-01
---
```

## Body

- `## Claim (fact, sourced)` — the sourced fact, cited inline with `[src-<ULID>]`.
- `## Grade` — why this confidence grade, referencing the sourcing behind it.
- `## Inference` — analyst reasoning drawn from the fact, clearly separated from the
  fact itself; allegation-aware language only (attribute, never assert guilt or
  liability).

## Confidence scale

- **A** confirmed — 2+ independent primary/authoritative sources
- **B** probable — 1 solid primary source, or 2 weak/secondary sources
- **C** unverified — single uncorroborated source
- **D** inference — analyst reasoning, not yet independently evidenced

## Inline citation tag (optional): `F-<lead>-<seq>`

Within a finding's own prose you may tag sub-claims `F-<lead-number>-<seq>` (e.g.
`F-12-01`, `F-12-02`) so other findings can cross-reference a specific sub-claim.
These tags are frozen and opaque to tooling once created — the id-integrity gate
accepts any `F-<n>-<n>` token without inspecting it. They are a convenience for
prose cross-reference, not a replacement for the `lead`/`sources` frontmatter fields
above.

## Example (synthetic)

`findings/example-trading-ltd-shared-registered-agent.md`:

```yaml
---
id: example-trading-ltd-shared-registered-agent
entities: [example-trading-ltd, example-holdings-bv]
confidence: B
status: open
lead: lead-01ARZ3NDEKTSV4RRFFQ69G5FAV
sources: [src-01ARZ3NDEKTSV4RRFFQ69G5FAW]
retrieved: 2026-01-01
---
## Claim (fact, sourced)
Example Trading Ltd and Example Holdings B.V. list the same registered agent,
"Acme Corporate Services", on their respective national company registers
[src-01ARZ3NDEKTSV4RRFFQ69G5FAW].

## Grade
Single primary-register source, uncorroborated by a second independent source →
**B** (would need a second register or filing to reach A).

## Inference
A shared registered agent is a coordination signal, not proof of common ownership
or control — registered-agent firms routinely serve many unrelated clients. Recorded
as an open lead for a possible common-control edge, not asserted as one.
```
