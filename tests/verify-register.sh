#!/usr/bin/env bash
# verify-register.sh — register-integrity gate. Every evidence path referenced in
# dossier/sources/register.yaml must exist on disk and be non-empty. Catches the silent
# false-success capture failure. Exits non-zero listing phantom references; 0 when clean.
# Usage: verify-register.sh [workspace-root]   (default: .)
set -uo pipefail
WS="${1:-.}"
REG="$WS/dossier/sources/register.yaml"
[ -f "$REG" ] || { echo "verify-register: no register at $REG (nothing to check)"; exit 0; }

python3 - "$WS" "$REG" <<'PY'
import sys, os, re, subprocess
ws, reg = sys.argv[1], sys.argv[2]
try:
    import yaml
except ImportError:
    print("verify-register: ERROR: pyyaml not available", file=sys.stderr); sys.exit(2)
data = yaml.safe_load(open(reg)) or []
entries = data.get("sources", []) if isinstance(data, dict) else data
if not isinstance(entries, list): entries = []
# Git-tracked paths (staged OR committed), relative to the repo root. None when ws is
# not a git work tree -> the tracked check is skipped (on-disk check still applies).
# Catches evidence captured to disk but never `git add`-ed (a present-but-uncommitted
# reference that the on-disk check alone passes).
tracked = None
try:
    r = subprocess.run(["git", "-C", ws, "ls-files", "-z"], capture_output=True, text=True)
    if r.returncode == 0:
        tracked = {p for p in r.stdout.split("\0") if p}
except Exception:
    tracked = None
def evidence_paths(v):
    # Yield every evidence/ path a field references. A field is an evidence reference
    # when its value (a string, or any element of a list) begins with "evidence/". A
    # single value may hold SEVERAL paths — a comma-joined folded YAML scalar
    # (``archive_url: >-``) or a comma/space-separated string — so split each path-valued
    # string and yield each token. Prose fields (e.g. sift_verdict) don't start with
    # "evidence/" and are skipped, so this doesn't false-match paths mentioned in text.
    for item in (v if isinstance(v, list) else [v]):
        if not isinstance(item, str) or not item.strip().startswith("evidence/"):
            continue
        for tok in re.split(r"[,\s]+", item.strip()):
            if tok.startswith("evidence/"):
                yield tok

missing, untracked, checked = [], [], 0
for e in entries:
    if not isinstance(e, dict): continue
    sid = e.get("id", "?")
    for k, v in e.items():
        for path in evidence_paths(v):
            checked += 1
            p = os.path.join(ws, path)
            if not (os.path.isfile(p) and os.path.getsize(p) > 0):
                missing.append(f"{sid}: {k} -> {path}")
            elif tracked is not None and path not in tracked:
                untracked.append(f"{sid}: {k} -> {path}")
if missing or untracked:
    if missing:
        print("VT-4 register integrity: PHANTOM evidence references (in register.yaml, not on disk):")
        for m in missing: print("   ", m)
    if untracked:
        print("VT-4 register integrity: UNCOMMITTED evidence references (on disk but not git-tracked"
              " -- `git add` them before committing):")
        for m in untracked: print("   ", m)
    sys.exit(1)
print(f"VT-4 register integrity: OK ({checked} evidence path(s) all present on disk and git-tracked)")
PY
