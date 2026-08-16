---
name: evaluate-run
description: The run-evaluator's procedure — compute metrics, judge reasoning/missing-tools, write the eval report, open an eval PR. Propose-only.
---

# evaluate-run

Authoritative procedure for evaluating ONE completed `osint_investigator` run. Follow top to bottom.

## Input
A `run_id` (e.g. `INV-SYNTH-01`), optionally a `conv_id`. Derive the run branch as
`run/<run_id>` unless told otherwise.

## Procedure
1. **Branch.** Create `eval/<run_id>` off this deployment's base branch (`${OSINT_BRANCH:-master}`;
   see `omnigent/run.sh` — MUST match its fallback exactly) — `git fetch origin "${OSINT_BRANCH:-master}" -q`,
   `git checkout -B eval/<run_id> "origin/${OSINT_BRANCH:-master}"`. Work only here.
2. **Metrics (objective).** Run:
   `python3 omnigent/eval/eval_metrics.py --run-id <run_id> --branch run/<run_id> --repo . --base-ref "origin/${OSINT_BRANCH:-master}" [--conv-id <conv_id>]`
   `--base-ref` MUST be passed and MUST use the same `${OSINT_BRANCH:-master}` fallback as step 1 / `omnigent/run.sh`. Without it the script falls back to `origin/main`; a deployment whose base branch is not `main` (e.g. `master`) would then resolve `run_base()` against a nonexistent ref and score empty/wrong metrics.
   It writes `dossier/runs/<run_id>-eval.metrics.json` and prints the JSON. Read it. The
   `verdict` (PASS / PASS_WITH_FLAGS / FAIL) and `hard_fail` are authoritative for the objective gate.
   The script auto-locates the most-recent prior eval's `.metrics.json` for the regression diff; pass `--prev-metrics <path>` only to override.
3. **Judgment (yours).** Use the `conv_id` from the metrics JSON (the `conv_id` field). If it is null, SKIP the coordinator-items fetch and judge from the sub-agent `.jsonl` transcripts only, noting the missing-coordinator gap in the report. Otherwise fetch the coordinator items
   (`curl -s "$OMNIGENT_URL/v1/sessions/<conv_id>/items?limit=1000&order=asc"`, where `<conv_id>` is that value, default host
   `http://omnigent:8000`) and read a sample of the sub-agent `.jsonl` named in the metrics
   (`agents[].file` under your workspace's Claude projects dir, `/root/.claude/projects/<munged-workspace-path>/`
   — `CLAUDE_PROJECTS_DIR` if set, else derived by `eval_metrics.py` from `--repo`'s absolute path with every
   non-alphanumeric character replaced by `-`). Assess:
   (a) **reasoning quality** — grade calibration (nothing >C without a 2nd source), allegation-aware
   language, any over/under-claim; (b) the single most valuable **missing tool/capability**;
   (c) **adjudicate each flag** — is it a real defect or benign? (a *good* `run_modified_tooling`
   change reads as benign).
   (d) **Per-agent review (hybrid).** Read the metrics `agents[]` block. For each **flagged**
   agent — `tool_auth_failures > 0`, `command_not_found`/`input_validation_errors > 0`, `delivered: false`, or `finding_grade` in (A, B) —
   read that one sub-agent transcript and assess: is the grade justified; did the degraded tool
   actually undermine the claim; did it deliver. Do NOT read clean agents (cost control).
   (e) **Tiered tool-health adjudication.** If `verification_integrity == "FAIL_CANDIDATE"`,
   confirm whether the ≥B claim's corroboration genuinely depended on the degraded tool: if yes,
   the report headline verdict is **FAIL**; if the primary evidence stands independently, keep
   **PASS_WITH_FLAGS** and say so. `reaped_after_completion: true` means the `failed` badge is the
   idle-reaper false-signal (work is gate-clean) — never read it as a real failure.
4. **Report.** Write `dossier/runs/<run_id>-eval.md` with sections: **Verdict** (the metrics verdict +
   the failing/ flagged conditions, with your adjudication); **Metrics** (a compact table from the JSON);
   **Regression** (the `regression` deltas, or "baseline — no prior eval"); **Judgment** (reasoning
   quality + missing-tool); **Per-Agent Review** — a table from `agents[]`: `| Agent | Role | Lead | Tools | Auth✗ | Search✗ |
   Delivered | Grade | Note |`. One line per clean agent; flagged agents carry your judgment note.
   In **Verdict**, list the tool-health flags (`degraded_tooling`, `degraded_search`) with your
   adjudication, and the headline verdict (escalated to FAIL only on a confirmed
   `verification_integrity`); **Proposals** (concrete backlog/skill changes as TEXT — e.g. `BL-x note: …`
   or a one-line skill-diff sketch — NOT applied).
5. **Deliver.** Commit `dossier/runs/<run_id>-eval.md` + `dossier/runs/<run_id>-eval.metrics.json` on
   `eval/<run_id>`. Push. Open a PR with `gh pr create`. END the session. Never push/merge `master`.

## Discipline
- PROPOSE-ONLY: do not edit the backlog, skills, or any dossier record — proposals are text in the report.
- The objective metrics are authoritative; your judgment adjudicates the flags and adds the qualitative read.
- If `eval_metrics.py` emits `_warnings` (a transcript was unreachable), note the gap in the report and
  evaluate on what landed — do not block.
