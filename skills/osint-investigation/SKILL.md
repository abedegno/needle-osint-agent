---
name: osint-investigation
description: Use when investigating companies, people, or a corporate web from documents and open sources - enforces a sourced, archived, confidence-graded OSINT methodology for an authorised private investigation. Records graded findings on companies AND named individuals into the dossier/ file structure.
---

# OSINT Investigation

Open-source investigation of companies AND the individuals behind them, for an authorised private investigation. Turns documents
and public records into a sourced, graded, archived dossier.

## When to use

Any time you are extending the investigation: ingesting a new document, researching an
entity, chasing a registry/domain lead, or recording findings.

## The dossier (where everything goes)

- `dossier/entities/<id>.md` — one company per file (frontmatter + narrative)
- `dossier/people/<id>.md` — one person per file
- `dossier/relationships.yaml` — edges (the web)
- `dossier/findings/<slug>.md` — discrete graded claims
- `dossier/timeline.md` — chronology
- `dossier/sources/register.yaml` — every source, archived + graded
- `evidence/documents/` — primary docs · `evidence/snapshots/` — captures

Templates for every record type: `references/templates.md`.

## Confidence scale (apply to every record, finding, and edge)

- **A** confirmed — 2+ independent primary/authoritative sources
- **B** probable — 1 solid primary source, or 2 weak/secondary
- **C** unverified — single uncorroborated source
- **D** inference/rumour — analyst reasoning, not yet evidenced

## The 6-phase loop

0. **Scope & ethics.** Confirm the work is authorised journalism. Apply OPSEC: do not
   contact or tip off subjects; prefer passive collection. Note what is in/out of scope.
1. **Seed extraction.** Harvest every identifier from documents already held — names,
   company numbers (ACN/ABN/KvK/CRN), phones, emails, domains, addresses, brands — and
   create seed entity files, each citing the document's source id.
2. **Registry & ownership.** Resolve each company in its registry (see
   `references/corporate-registries.md`). Capture directors, shareholders/owners,
   incorporation date, registered address, status. Flag likely shells (virtual offices,
   mass-registration agents, mobile-only contacts).
3. **Infrastructure.** Investigate domains and hosting (see `references/domain-infra.md`):
   WHOIS/RDAP, DNS, reverse-IP, certificate transparency, shared analytics/ad IDs,
   archived versions. Use these to surface hidden links between entities.
4. **Corroboration.** Cross-reference everything. Shared addresses, phones, emails,
   people, branding, or infrastructure become edges in `relationships.yaml`, each graded.
5. **Verification.** Apply SIFT to every source (see `references/source-verification.md`).
   Archive it (crawl4ai capture into `evidence/snapshots/` AND a Wayback `save` URL)
   BEFORE relying on it. Hash it, assign A/B/C/D, log it in `sources/register.yaml`.
   Downgrade any claim that loses corroboration.
6. **Reporting.** Update entity files, the timeline, and the relationship web. Update
   `entities/_index.md`. List the strongest open leads for the next pass.

## Hard rules (non-negotiable)

- **No uncited claims.** Every assertion in a record carries a `src-<ULID>` id (minted via
  `omnigent/bin/mint-id.sh src`). Uncited text is marked `(UNVERIFIED)`.
- **Archive before relying.** Web sources can vanish — capture them first.
- **Fact vs inference.** Keep sourced facts and analyst inference visibly separate.
- **Allegation vs established (accuracy, not caution).** Record an allegation *as* an
  allegation because that is the true state of the evidence — "filing X alleges Y" is a
  sourced fact; "Y is established" needs its own proof. This is a grading matter, not
  defamation caution. The dossier is private research, not a publication: name real people
  and state graded conclusions plainly. Publication-grade caution (anonymisation,
  defamation/legal review) applies ONLY to anything later published — never to the research.
- **Corrections, not deletions.** A disproven finding is struck through with a dated note,
  never silently removed.
- **People are first-class.** Every named individual tied to the web gets a
  `dossier/people/<id>.md` (a stub with the real name + `(UNVERIFIED)` + leads, even at
  grade C/D); promote with corroboration. Never pseudonymise or omit a name. Person↔entity
  and person↔person links are graded edges in `relationships.yaml`.
- **Intermediaries and counterparties are part of the web — never drop them as "just
  courtroom parties."** Professional intermediaries (legal counsel / law firms, registered &
  resident agents, trademark/filing agents, accountants, company-formation services) and
  commercial counterparties (suppliers, competitors, and litigation claimants/defendants that
  are themselves businesses in the relevant trade) are first-class nodes — a firm is an
  `entity`, a named professional a `person`. A **shared** intermediary across two otherwise-
  separate entities — the same agent of record, registered agent, law firm or accountant — is
  among the strongest coordination / common-control signals: record it as a graded
  `shared_agent` / `shared_counsel` / `shared_registered_agent` edge in `relationships.yaml`
  with sources. A competing or supplying manufacturer that sues (or is sued by) a group entity
  is a material node in the supply web, not a party to discard. (Pure private tort plaintiffs —
  e.g. an injured consumer — and their personal-injury counsel are lower priority: capture at
  C/D only if named, but ALWAYS capture counsel or a firm that recurs across more than one
  matter or entity.)

## ID conventions

- **Source ids** (`src-<ULID>`) and **lead ids** (`lead-<ULID>`) are minted via `omnigent/bin/mint-id.sh src` or `omnigent/bin/mint-id.sh lead` respectively — never hand-write ids or assume the next number.
- **Evidence filenames** may embed the source id (e.g. `evidence/snapshots/<src-ULID>_domain-lookup.md`, `evidence/snapshots/<src-ULID>_filing.pdf`).
- **Finding ids** (`F-xxx-yy` in finding filenames) are stable across the dossier migration. Cross-document references to findings should cite the finding **slug** (the stable identifier). A qualified F-reference scheme is deferred; treat existing F-ids as document-local for now.

## Tooling

- **crawl4ai** (MCP, `http://localhost:11235/mcp/sse`) — fetch/crawl/markdown/screenshot
  of web sources; primary collection + snapshot engine.
- **WebSearch / WebFetch** — discovery when crawl4ai is not running.
- Additional MCP servers (e.g. a corporate-registry API) are added to `.mcp.json` as
  leads require them.
