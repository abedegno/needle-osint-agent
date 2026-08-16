---
name: run-investigation
description: The coordinator's per-run procedure — drain the open lead queue by dispatching researcher then verifier per lead, record graded findings, run the analyst for next-run leads, then commit and open a PR.
---

# run-investigation

Authoritative procedure for one investigation run. Follow it top to bottom. The
methodology rules (confidence scale, SIFT, archiving, allegation-aware language,
corrections-not-deletions) live in `omnigent/skills/osint-investigation` and govern.

## Procedure

> **PREFLIGHT-ONLY mode.** If the launch prompt begins with "PREFLIGHT ONLY", run ONLY step 2's probes
> (2b–2c), then write a per-harness health report (each harness → `RESULT: PASS|FAIL` AND
> `SKILL-LOAD: PASS|FAIL`, plus any `MISSING:`/`FAILED:` items) as your final message and STOP. Do not
> branch, work leads, record findings, or commit — regardless of the outcome.

1. **Orient.** Read `dossier/leads.yaml` and the current dossier (entities,
   relationships, sources/register). Capture the set of leads with `status: open`
   right now — this is the run's WORK SET. Do not add to the work set later.
2. **Preflight (fail-hard health gate).**
   a. `sys_os_shell("command -v claude codex || true")` — route only to available workers.
   b. For EACH worker harness this run will use (`researcher` = claude-sdk, `verifier` = codex-native),
      dispatch a selftest probe IN THE SAME TURN, then end the turn and await the inbox:
      `sys_session_send(agent="researcher", title="preflight-researcher", args={purpose:"explore",
      input:"Run exactly this one command: bash omnigent/bin/harness-selftest.sh — then report its
      FULL stdout and the exit code. Then load the 'osint-investigation' skill using WHICHEVER
      skill-loading tool your harness provides (load_skill(\"osint-investigation\") on codex; the
      native Skill tool on claude-sdk/claude-native — use your own harness's tool, not the other
      one's name) and check the returned content: it must be non-empty and contain the heading text
      'Hard rules (non-negotiable)' (a distinctive anchor from the methodology skill). Report a
      second line 'SKILL-LOAD: PASS' if both hold, or 'SKILL-LOAD: FAIL' with 'MISSING:
      osint-investigation' and the reason (did not load / empty / anchor text absent) if either
      fails. Do nothing else: do not research, snapshot, or edit anything."})`
      and the same for `agent="verifier", title="preflight-verifier"` (`purpose:"review"`).
   c. **Bounded, #848-safe wait.** Await each probe's report. If a probe's result has not arrived after
      a few `sys_read_inbox` polls, call `sys_session_get_history` on that probe's session and read its
      completed output there. If a probe NEITHER delivers to the inbox NOR shows a completed `RESULT:`
      line within that budget, treat that harness as **FAILED** (a non-delivering harness is itself the
      defect this gate guards against).
   d. **Decision (fail-hard).** If EVERY probe reports BOTH `RESULT: PASS` AND `SKILL-LOAD: PASS` →
      proceed to step 3. If ANY probe reports `RESULT: FAIL` or `SKILL-LOAD: FAIL`, or non-delivers /
      cannot be confirmed → **ABORT**: write
      `dossier/runs/<run-id>-preflight-FAILED.md` recording, per failing harness, its `MISSING:` /
      `FAILED:` items and the fix — for a tool/auth `MISSING:`/`FAILED:` item, "that harness shell is
      missing those keys — add them to `OMNIGENT_RUNNER_ENV_PASSTHROUGH` for that harness, per your
      deployment's runner env-passthrough config"; for a `SKILL-LOAD: FAIL` / `MISSING:
      osint-investigation`, "that harness cannot resolve the `osint-investigation` skill — check its
      per-harness skill-discovery path (e.g. the `.claude/skills/osint-investigation` symlink for
      codex's bare-name lookup) still resolves to `omnigent/skills/osint-investigation`". Do NOT create
      the run branch, do NOT work any lead, do NOT commit dossier changes. END the run with that report
      as your final message.
3. **Branch.** Create `run/INV-<YYYYMMDD>-<NN>` (NN = next number not already a
   branch/PR). Work only on this branch.
4. **Per lead** (in priority order, up to param `max_leads_per_run`):
   a. Mark the lead `in_progress` in `leads.yaml`. Mint every new `src` and `lead` id
      with `omnigent/bin/mint-id.sh src` (or `lead`) — never hand-write a number or
      "take the next id".
   b. Dispatch `researcher`: `sys_session_send(agent="researcher",
      title="research-<lead-id>", args={purpose:"explore",
      input:"<entity + question + any notes from the lead>"})`. Emit in the same
      turn, then end the turn and await the inbox.
   c. On the researcher's report, dispatch `verifier`:
      `sys_session_send(agent="verifier", title="verify-<lead-id>",
      args={purpose:"review", input:"<the claims + their sources>"})`.
   d. On the verifier's verdicts, YOU record the results: add/append a source entry
      per corroborated source in `dossier/sources/register.yaml` (with archive path
      + retrieval date); create/update `dossier/entities/<id>.md` for companies,
      `dossier/people/<id>.md` for EVERY named individual (from the template — a stub
      with the real name + `(UNVERIFIED)` + leads, even at grade C/D), and
      `dossier/findings/<slug>.md` for each discrete graded claim; append corroborated
      person↔entity / person↔person / entity↔entity edges to
      `dossier/relationships.yaml`. Set the lead `done` (or `blocked` with a reason).
      Record real names plainly — do NOT pseudonymise (private research, not a
      publication). Record anything above grade C only with an independent 2nd source.
5. **Synthesize (once).** Dispatch `analyst`:
   `sys_session_send(agent="analyst", title="synthesize-INV-<date>",
   args={purpose:"explore", input:"<the run's verified findings>"})`. Merge its
   proposed edges into `relationships.yaml`, and append its proposed leads to
   `leads.yaml` with `status: open`, `created_by: analyst` — these are for the NEXT
   run; do NOT work them now.
6. **Deliver.** Write `dossier/runs/INV-<YYYYMMDD>-<NN>.md` (Leads worked with per-lead
   rollup grade, Findings with grades + source ids, New edges, New leads,
   Blocked/needs-human).
   - **Grades come from the finding docs — never re-graded here.** For each lead, read its
     `dossier/findings/*.md` `verifier_grades` map (or the single `confidence:` value on
     older-format docs). The **per-lead rollup grade** (shown once per lead in the
     Leads-Worked table and the PR body) is the **strongest grade present** in that map
     (A > B > C > D) — the same rule the evaluator uses. Do not average, take the modal
     grade, or eyeball it.
   - **Copy per-finding grades verbatim and complete.** The "Findings with grades" section
     lists **every** `F-xxx-yy` from each lead's finding doc with its **exact** grade from
     `verifier_grades` — do not summarize, re-grade, or list a subset. The count of rows
     for a lead must equal the size of its `verifier_grades` map.
   - **Stage EVERYTHING first — always `git add -A`.** Stage not just the narrative
     files you wrote (entities/people/findings/relationships/leads/run report) but also
     the captures under `evidence/` and the updated `dossier/sources/register.yaml`. A
     per-file `git add` silently drops the evidence and the register, leaving findings
     unbacked in the pushed branch. NEVER hand-list paths; `git add -A`.
   - **Evidence gate (AFTER staging, before the commit):** run
     `bash omnigent/tests/verify-register.sh .`. It must exit 0 — every `evidence/` path
     in `register.yaml` must exist on disk AND be git-tracked. If it FAILS: **PHANTOM** =
     a reference with no file on disk (re-capture with `omnigent/bin/capture-evidence.sh`,
     or remove the bogus reference); **UNCOMMITTED** = a captured file that was not staged
     (you skipped `git add -A` — stage it). Commit only once the gate passes.
   - **ID-integrity gate (AFTER staging, before the commit):** run
     `bash omnigent/tests/verify-id-integrity.sh .`. It must exit 0 — every `src`/`lead`
     id resolves to a definition, no legacy `src-N`/`lead-N` ids survive, and ids are
     unique in scope. Mint new ids ONLY with `omnigent/bin/mint-id.sh src|lead` (never
     hand-write a number); if the gate FAILS it names the offending id (a dangling
     reference, a hand-numbered legacy id, or a malformed id). Commit only once it passes.
   - Commit (per lead, or once at the end — but `git add -A` first every time, so the
     evidence and register always ride along). Push the branch. Open a PR with
     `gh pr create` using the same sections and the same per-lead rollup grades. Then END
     the session. Never push to or
     merge `master`.

## Discipline
- Act in the same turn you announce; after a dispatch, end the turn and let the
  inbox wake you. Never busy-poll.
- The verifier's grade is authoritative — do not upgrade a finding yourself.
- There is **no degraded mode**: if a worker harness is unavailable, fails its
  selftest (e.g. `codex`/the `verifier` can't boot, or a harness is missing a key), or
  cannot resolve the `osint-investigation` skill (`SKILL-LOAD: FAIL`), step 2's
  fail-hard preflight gate **aborts the run** before any lead is worked — you do not
  proceed self-grading, capping at C, or reciting the methodology from memory. Fix the
  environment (or the harness's skill-discovery path) and relaunch.
