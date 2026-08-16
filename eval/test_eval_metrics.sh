#!/usr/bin/env bash
# Self-contained test for eval_metrics.py. Builds a SYNTHETIC git repo (its own remote, so
# origin/<branch> refs exist) and drives eval_metrics.py through its real SUCCESS path entirely
# offline — no LAN, no omnigent API, no private runner transcripts, no historical INV-IDs.
#
# Run directly:
#   bash omnigent/eval/test_eval_metrics.sh
#
# The evaluator contract this fixture exercises (see eval_metrics.py):
#   1. run_base() finds the branch point as the parent of the EARLIEST commit on
#      origin/<branch> whose subject contains --run-id (`git log --grep=<run-id>`).
#   2. gate_metrics() does `git worktree add` for origin/<branch> and runs
#      `bash omnigent/tests/verify-register.sh .` inside it; gate.exit is that script's exit.
#   3. The evaluator itself fetches `origin <branch>` and addresses origin/<branch> throughout,
#      so the fixture must be its own remote.
#   4. With OMNIGENT_URL unreachable, API-derived metrics degrade to warnings/None while
#      git-derived metrics (branch diff, gate, findings) still compute offline.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ok(){ printf '  \033[32m\xe2\x9c\x85\033[0m %s\n' "$1"; }
skip(){ printf '  \033[33m\xe2\x8f\xad\033[0m  SKIP: %s\n' "$1"; exit 77; }

command -v git >/dev/null 2>&1 || skip "git not found"
command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null \
  || skip "no python3 with pyyaml on PATH (verify-register.sh needs it)"

WS="$(mktemp -d)"; trap 'rm -rf "$WS"' EXIT

# --- Step 1: init the synthetic repo -----------------------------------------------------------
git init -q -b main "$WS" 2>/dev/null || { git init -q "$WS" && git -C "$WS" checkout -q -b main; }
git -C "$WS" config user.email "eval-fixture@example.invalid"
git -C "$WS" config user.name  "Eval Fixture"

mkdir -p "$WS/omnigent/tests" "$WS/dossier/sources" "$WS/dossier/findings" "$WS/evidence/snapshots"
cp "$HERE/../tests/verify-register.sh" "$WS/omnigent/tests/verify-register.sh"

# --- Step 2: seed content on main (baseline; not counted in the run's grade tally) --------------
cat > "$WS/evidence/snapshots/seed-src.md" <<'EOF'
Synthetic seed evidence snapshot (fixture only, not a real capture).
EOF

cat > "$WS/dossier/sources/register.yaml" <<'EOF'
- id: src-SYNTH0001
  title: "Synthetic seed source"
  type: primary_register
  origin: "Synthetic Fixture Registry"
  url: null
  archive_url: "evidence/snapshots/seed-src.md"
  retrieved: "2026-01-01"
  sha256: "0000000000000000000000000000000000000000000000000000000000000000"
  sift_verdict: "Synthetic fixture source; not a real register entry."
EOF

cat > "$WS/dossier/leads.yaml" <<'EOF'
- id: lead-90001
  target: synthetic-target-alpha
  question: "Synthetic seed lead for the eval_metrics fixture."
  type: registry
  priority: 1
  status: done
  created_by: seed
  sources: [src-SYNTH0001]
  notes: Synthetic fixture lead; not a real investigation.
- id: lead-90002
  target: synthetic-target-beta
  question: "Second synthetic seed lead for the eval_metrics fixture."
  type: registry
  priority: 1
  status: done
  created_by: seed
  sources: [src-SYNTH0001]
  notes: Synthetic fixture lead; not a real investigation.
EOF

cat > "$WS/dossier/findings/seed-finding.md" <<'EOF'
---
id: seed-finding
entities: [synthetic-target-alpha]
confidence: A   # baseline finding on main; predates the run branch, excluded from its diff
status: verified
lead: lead-90001
sources: [src-SYNTH0001]
retrieved: "2026-01-01"
---

## Claim (fact, sourced)
Synthetic seed finding used only to exercise `verify-register.sh` / `gate_metrics`. Not real
investigative content [src-SYNTH0001].
EOF

git -C "$WS" add -A
git -C "$WS" commit -q -m "seed: synthetic dossier fixture for eval_metrics test"

# --- Step 3: run branch with two graded findings — known truth: B=1, C=1 -----------------------
git -C "$WS" checkout -q -b run/INV-SYNTH-01

cat > "$WS/evidence/snapshots/synth-b-src.md" <<'EOF'
Synthetic branch evidence snapshot backing the B-grade finding (fixture only).
EOF
cat > "$WS/evidence/snapshots/synth-c-src.md" <<'EOF'
Synthetic branch evidence snapshot backing the C-grade finding (fixture only).
EOF

cat > "$WS/dossier/sources/register.yaml" <<'EOF'
- id: src-SYNTH0001
  title: "Synthetic seed source"
  type: primary_register
  origin: "Synthetic Fixture Registry"
  url: null
  archive_url: "evidence/snapshots/seed-src.md"
  retrieved: "2026-01-01"
  sha256: "0000000000000000000000000000000000000000000000000000000000000000"
  sift_verdict: "Synthetic fixture source; not a real register entry."
- id: src-SYNTH0002
  title: "Synthetic B-grade corroborating source"
  type: secondary_aggregator
  origin: "Synthetic Fixture Registry"
  url: null
  archive_url: "evidence/snapshots/synth-b-src.md"
  retrieved: "2026-01-02"
  sha256: "1111111111111111111111111111111111111111111111111111111111111111"
  sift_verdict: "Synthetic fixture source; not a real register entry."
- id: src-SYNTH0003
  title: "Synthetic C-grade single source"
  type: secondary_aggregator
  origin: "Synthetic Fixture Registry"
  url: null
  archive_url: "evidence/snapshots/synth-c-src.md"
  retrieved: "2026-01-02"
  sha256: "2222222222222222222222222222222222222222222222222222222222222222"
  sift_verdict: "Synthetic fixture source; not a real register entry."
EOF

cat > "$WS/dossier/findings/synth-finding-b.md" <<'EOF'
---
id: synth-finding-b
entities: [synthetic-target-alpha]
confidence: B
status: verified
lead: lead-90001
sources: [src-SYNTH0002]
retrieved: "2026-01-02"
---

## Claim (fact, sourced)
Synthetic B-grade finding: independent corroboration from a synthetic secondary source
[src-SYNTH0002].
EOF

cat > "$WS/dossier/findings/synth-finding-c.md" <<'EOF'
---
id: synth-finding-c
entities: [synthetic-target-beta]
confidence: C
status: verified
lead: lead-90002
sources: [src-SYNTH0003]
retrieved: "2026-01-02"
---

## Claim (fact, sourced)
Synthetic C-grade finding: single uncorroborated synthetic source [src-SYNTH0003].
EOF

git -C "$WS" add -A
git -C "$WS" commit -q -m "INV-SYNTH-01: add two synthetic findings (B, C)"

# --- Step 4: make the workspace its own remote so origin/<branch> refs exist -------------------
git -C "$WS" remote add origin "$WS"
git -C "$WS" fetch -q origin

# --- Step 5: run the evaluator fully offline and assert the known-truth SUCCESS result ----------
OMNIGENT_URL="http://127.0.0.1:1" python3 "$HERE/eval_metrics.py" \
  --run-id INV-SYNTH-01 --branch run/INV-SYNTH-01 --conv-id conv_synth \
  --base-ref origin/main --repo "$WS" --out "$WS/out.json" >/dev/null

python3 - "$WS/out.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
# Schema (eval_metrics.py): result["gate"]["exit"], result["hard_fail"]["gate_fail"] (bool),
# result["verdict"] is a STRING ("PASS"|"PASS_WITH_FLAGS"|"FAIL"), grades under
# result["findings"]["grade_tally"] (single-letter keys).
assert r["gate"]["exit"] == 0, f'gate not clean: {r["gate"]}'
assert r["hard_fail"]["gate_fail"] is False, r["hard_fail"]
assert r["verdict"] != "FAIL", r["verdict"]
tally = r["findings"]["grade_tally"]
assert tally.get("B") == 1 and tally.get("C") == 1, tally
print(f'synthetic eval SUCCESS-path asserted: gate.exit={r["gate"]["exit"]} '
      f'gate_fail={r["hard_fail"]["gate_fail"]} verdict={r["verdict"]} tally={tally}')
PY

ok "synthetic eval_metrics SUCCESS path (gate clean, hard_fail.gate_fail=False, verdict!=FAIL, tally B=1/C=1)"

# --- Step 6: regression — an UNRESOLVABLE eval base must FAIL CLOSED, not silent-zero PASS ------
# run-id absent from every commit subject (run_base's --grep primary path misses) AND a
# nonexistent --base-ref (the merge-base fallback can't resolve either) => hard_fail forces
# verdict FAIL, so bad-base metrics can never read as an authoritative PASS (Codex review).
OMNIGENT_URL="http://127.0.0.1:1" python3 "$HERE/eval_metrics.py" \
  --run-id INV-NOMATCH-99 --branch run/INV-SYNTH-01 --base-ref origin/nonexistent-base \
  --repo "$WS" --out "$WS/out-badbase.json" >/dev/null 2>&1 || true
python3 - "$WS/out-badbase.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
assert r["hard_fail"].get("unresolved_eval_base") is True, f'expected unresolved_eval_base hard_fail, got {r["hard_fail"]}'
assert r["verdict"] == "FAIL", f'expected verdict FAIL for an unresolvable base, got {r["verdict"]}'
print(f'unresolvable-base regression: unresolved_eval_base=True verdict={r["verdict"]}')
PY
ok "unresolvable eval base fails CLOSED (hard_fail.unresolved_eval_base=True, verdict=FAIL)"

# --- Step 7: an EXISTING but UNRELATED (orphan) base must ALSO fail closed ---------------------
# Ref EXISTENCE is not enough: an orphan branch shares NO history with the run branch, so
# git merge-base is empty and a diff against it is invalid. It must hard-fail too (Codex round-2:
# an existing-but-unrelated ref previously slipped past the existence-only check).
git -C "$WS" checkout -q --orphan orphan-base
git -C "$WS" rm -rf -q . >/dev/null 2>&1 || true
echo unrelated > "$WS/unrelated.txt"; git -C "$WS" add unrelated.txt
git -C "$WS" -c user.email=t@t -c user.name=t commit -qm "orphan: unrelated history" >/dev/null
git -C "$WS" fetch -q origin
git -C "$WS" checkout -qf main
OMNIGENT_URL="http://127.0.0.1:1" python3 "$HERE/eval_metrics.py" \
  --run-id INV-NOMATCH-98 --branch run/INV-SYNTH-01 --base-ref origin/orphan-base \
  --repo "$WS" --out "$WS/out-orphan.json" >/dev/null 2>&1 || true
python3 - "$WS/out-orphan.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
assert r["hard_fail"].get("unresolved_eval_base") is True, f'orphan (existing-but-unrelated) base should hard-fail, got {r["hard_fail"]}'
assert r["verdict"] == "FAIL", f'orphan base should FAIL, got {r["verdict"]}'
print(f'orphan-base regression: unresolved_eval_base=True verdict={r["verdict"]}')
PY
ok "existing-but-unrelated (orphan) eval base ALSO fails CLOSED"

exit 0
