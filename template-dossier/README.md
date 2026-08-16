# Template dossier

This is the schema template for a fresh case dossier. It ships with the engine
(`omnigent/`) so it is fully synthetic — every example below uses a fictional
company ("Example Trading Ltd") and a fictional person ("Jane Example"). Copy this
directory's structure into your own private `dossier/` at the repo root (a sibling
of `omnigent/`, never committed under `omnigent/`) and replace the examples with
your own case's real data.

## Layout

| Path | Purpose |
|---|---|
| `case-brief.md.example` | Copy to `dossier/case-brief.md` and fill in your case identity. The coordinator prompt reads this file to learn what case it is working. |
| `leads.yaml` | The lead queue the coordinator drains each run. |
| `sources/register.yaml` | Every source cited anywhere in the dossier — archived and graded. |
| `entities/` | One file per company/organisation. |
| `people/` | One file per named individual. |
| `findings/` | Discrete, graded claims — the atomic unit of evidence. |
| `relationships.yaml` | The edges connecting entities/people (the web). |

Each of `entities/`, `people/`, and `findings/` carries its own `README.md` with the
frontmatter schema and a tiny synthetic example. Read those before adding your first
real record.

## Id conventions — read this before minting anything

Two identifier families exist in the dossier:

1. **`src-<ULID>` and `lead-<ULID>`** — canonical, collision-safe ids for every source
   and every lead. **Mint every new one with `omnigent/bin/mint-id.sh src` or
   `omnigent/bin/mint-id.sh lead`. Never hand-write a number.** Hand-numbering is what
   causes collisions across parallel or unmerged runs, because it relies on a shared
   counter; ULIDs don't need one.

   ```console
   $ omnigent/bin/mint-id.sh lead
   lead-01ARZ3NDEKTSV4RRFFQ69G5FAV
   $ omnigent/bin/mint-id.sh src
   src-01ARZ3NDEKTSV4RRFFQ69G5FAW
   ```

2. **Slug ids** for `entities/`, `people/`, and `findings/` — the filename (minus
   `.md`) IS the id, e.g. `entities/example-trading-ltd.md` has
   `id: example-trading-ltd`. Slugs are kebab-case and human-readable, and they are
   **permanent once created** — other records reference them (`linked_entities`, a
   finding's `entities:` list, relationship edges), so never rename a slug after
   anything else cites it.

3. **`F-<lead>-<seq>` inline citation tags (optional)** — inside a finding's own
   prose you may tag sub-claims `F-<lead-number>-<seq>` (e.g. `F-12-01`, `F-12-02`)
   so other findings can cross-reference a specific sub-claim. These tags are a
   convenience for prose, not a replacement for the `lead`/`sources` frontmatter
   fields — once created they are frozen and opaque to tooling (the id-integrity
   gate accepts any `F-<n>-<n>` token without inspecting it). Don't confuse an
   `F-NN` tag with a `lead-<ULID>` id.

### DELIVER gate — id integrity

Before any run or commit is considered done, run:

```bash
omnigent/tests/verify-id-integrity.sh
```

This is a **mandatory DELIVER gate**: every `src-`/`lead-` reference anywhere in the
dossier must resolve to a real, defined id; no legacy hand-numbered ids may exist;
every id must be unique in its scope. A run or PR that fails this gate is not done.

## Confidence scale

Apply to every record, finding, and edge:

- **A** confirmed — 2+ independent primary/authoritative sources
- **B** probable — 1 solid primary source, or 2 weak/secondary sources
- **C** unverified — single uncorroborated source
- **D** inference — analyst reasoning, not yet independently evidenced

## Full methodology

See the `osint-investigation` skill (`omnigent/skills/osint-investigation/`) for the
six-phase collection/verification loop, source SIFT verification, and the hard rules
(no uncited claims, allegation-aware language, archive-before-relying-on-a-source,
etc). This README covers the file layout and id conventions only.
