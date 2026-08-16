# needle-osint-agent

An autonomous, source-graded OSINT investigation engine built to run on omnigent,
an agent-orchestration platform for long-running, multi-agent bundles. It turns a
starting case brief into a growing, cited, confidence-graded dossier of
companies, people, and the relationships between them — by repeatedly draining a
lead queue with a coordinator that delegates collection, verification, and
synthesis to three sub-agents, and opening a pull request every run.

This repository is the **engine**: the coordinator, sub-agents, skills, and
tooling. It carries no case data of its own. You point it at your own case by
creating a private `dossier/` (never committed here) from the shipped template.

## Install & layout

This repository **is** the engine bundle, and it runs as a directory named
`omnigent/` inside a *workspace* (a git repo of your own) that also holds your
private `dossier/`. Every path in this README (`omnigent/run.sh`,
`omnigent/.env.example`, `omnigent run omnigent/`) and the agents' own
`omnigent/bin/...` / sibling-`dossier/` references assume that layout — so you
install this repo **at `omnigent/`, not at your workspace root**:

```
my-investigation/          # your workspace (a git repo); run everything from here
├── omnigent/              # THIS repository, vendored here — NOT the workspace root
├── dossier/               # your private case data (see "Point it at your case")
├── .env                   # copied from omnigent/.env.example
└── .mcp.json              # copied from omnigent/.mcp.json.example
```

**For a scheduled/deployment runner (`run.sh`) — vendor with `git subtree`.** This
copies the engine's files *into your own workspace repo* as commits:

```bash
cd my-investigation      # YOUR workspace repo — must already exist and have an `origin` remote
git subtree add --prefix=omnigent https://github.com/abedegno/needle-osint-agent main --squash
git push                 # publish the vendored engine to your workspace's origin
```

`--squash` records each engine version as a single commit in your history rather
than importing all of upstream's commits — **use it consistently** on `add` and
`pull` (a `--squash` add and a non-`--squash` pull have no common ancestor and git
will refuse the update).

How `run.sh` stays current: it `git pull`s **your workspace repo from its own
`origin`** before each run — so it tracks whatever engine version is committed and
pushed to *your* repo, **not** this upstream directly. `git subtree add` imports a
one-time snapshot and does not configure any remote; to take a newer engine
release, pull it into the subtree and push it to your workspace, yourself:

```bash
git subtree pull --prefix=omnigent https://github.com/abedegno/needle-osint-agent main --squash
git push
```

`run.sh` therefore needs your workspace to be a git repo with an `origin` remote
and the branch it checks out (`${OSINT_BRANCH:-master}` — set `OSINT_BRANCH` to
match your workspace's default branch if it isn't `master`).

**Or plain-clone the engine into an `omnigent/` subdirectory** (a nested repo,
separate from your workspace):

```bash
git clone https://github.com/abedegno/needle-osint-agent omnigent
```

With a plain clone, `run.sh`'s auto-pull won't update the engine (it pulls the
workspace repo, not this nested clone) — update it yourself with `git -C omnigent
pull` and launch the bundle directly rather than via `run.sh`.

**Whichever way you install it**, the coordinator cannot investigate until you set
up your case: create and seed a sibling `dossier/` and copy the config examples
(see *Point it at your case* and *Configure* below), and make the workspace a git
repo — each run creates a branch, commits, and opens a PR, so a real run also needs
a remote to push to. *Run it on omnigent* then covers launching, with `omnigent run
omnigent/` or `run.sh`.

Do **not** run from a bare checkout of this repo's own root: the launcher and the
agents resolve paths relative to the workspace and expect the engine at `omnigent/`
(`omnigent/run.sh` refuses to run otherwise).

## What it does

- **Coordinator** (`osint_investigator`, `config.yaml`) drains `dossier/leads.yaml`
  each run, dispatching:
  - **researcher** — discovers sources (SearXNG web search), fetches and snapshots
    them (crawl4ai MCP for pages, shell capture for screenshots/PDFs), and returns
    a sourced report for one lead. Collects, never concludes.
  - **verifier** — SIFTs each finding, actively tries to refute it, requires an
    independent second source before any claim clears grade C, and assigns a
    confidence grade (A–D).
  - **analyst** — reads the run's verified findings and proposes new entity/people
    nodes, relationship edges, and leads for the *next* run.
- The coordinator itself records graded findings into the dossier, commits, and
  opens a PR. It never pushes to or merges the base branch, and it never does
  collection or grading itself.
- A separate **run-evaluator** bundle (`eval/`) scores a completed run against
  deterministic metrics, judges the reasoning trace, and opens a propose-only eval
  PR (nothing is applied automatically).

Full methodology — the confidence scale, SIFT verification, source archiving,
allegation-aware language, and the six-phase collection loop — lives in
`skills/osint-investigation/`; it is the source of truth the coordinator and every
sub-agent defer to.

## Repository layout

| Path | Purpose |
|---|---|
| `config.yaml` | The coordinator bundle definition (`osint_investigator`). |
| `run.sh` | Stateless launcher for the omnigent runner: pulls the deployment branch, then execs the bundle. |
| `agents/` | Per-sub-agent bundle definitions (`researcher`, `verifier`, `analyst`) and their MCP tool configs. |
| `skills/` | The methodology and per-role procedures every agent follows (`osint-investigation`, `run-investigation`, `research-lead`, `verify-finding`, `synthesize`). |
| `bin/` | Collection tooling: registry/API clients (Companies House, GLEIF, CourtListener, USPTO, UK Gazette, WIPO), evidence capture, ULID id minting. |
| `template-dossier/` | The schema and synthetic examples for a fresh case dossier — copy this to your own private `dossier/`. |
| `eval/` | The run-evaluator bundle, its metrics tool, and its procedure skill. |
| `tests/` | Unit tests and capability checks. |

## Point it at your case

Case data never lives under this directory. In your workspace, alongside
`omnigent/`, create a sibling `dossier/`:

1. Copy the shape of `omnigent/template-dossier/` into `dossier/` (in the workspace, next to `omnigent/`):
   `entities/`, `people/`, `findings/`, `sources/register.yaml`,
   `relationships.yaml`, `leads.yaml`.
2. Copy `omnigent/template-dossier/case-brief.md.example` to `dossier/case-brief.md` and
   replace every placeholder with your case's real authorisation, subject, target
   entities, and starting questions. The coordinator prompt reads this file at the
   start of every run — without it, there is no case to investigate.
3. Seed `dossier/leads.yaml` with your first lead(s).

Read `omnigent/template-dossier/README.md` before writing your first record — it
covers the file layout, the two id families (`src-`/`lead-` ULIDs vs. permanent
slug ids), and the mandatory id-integrity DELIVER gate
(`omnigent/tests/verify-id-integrity.sh`).

## Configure

Copy the two example files to your workspace root (next to `omnigent/`) and fill
in what you need:

```bash
cp omnigent/.env.example .env
cp omnigent/.mcp.json.example .mcp.json
```

`.env.example` documents every environment variable the tooling reads, and which
sources need a (free) registration and which are keyless. Nothing is required to
start: crawl4ai and SearXNG default to `localhost`, and GLEIF, the UK Gazette, and
WIPO need no key at all.

`.mcp.json.example` is the MCP server registration for the two live tools the
sub-agents use directly: crawl4ai (fetch + snapshot) and SearXNG (search). Point
the URLs at your own deployment of each.

## Run it on omnigent

The coordinator is an omnigent bundle. From a workspace that has this engine at
`omnigent/` and your `dossier/` alongside it:

```bash
omnigent run omnigent/ --server "${OMNIGENT_SERVER:-http://omnigent:8000}"
```

`run.sh` is the stateless entry point a scheduled runner (cron, n8n, the omnigent
runner host) uses instead: it checks out `${OSINT_BRANCH:-master}`, fast-forward
pulls it, and execs the bundle. Set `OSINT_BRANCH=main` if your deployment's
default branch is `main`. `OSINT_PRINT_RESOLVED=1 omnigent/run.sh` prints the
effective branch/remote/server without doing any git operation, for a dry-run
sanity check.

Before any run or commit is considered done, the id-integrity gate must pass
(run from your workspace, with the engine at `omnigent/`):

```bash
omnigent/tests/verify-id-integrity.sh
```

To run the collection/capability tests locally:

```bash
omnigent/tests/run-capability-suite.sh
```

To evaluate a completed run, launch the `run_evaluator` bundle
(`omnigent/eval/config.yaml`) with the run id — see
`omnigent/eval/skills/evaluate-run/SKILL.md` for the full procedure.

## License

MIT — see `LICENSE`.
