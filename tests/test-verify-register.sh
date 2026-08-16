#!/usr/bin/env bash
# Test for verify-register.sh — the register-integrity gate. Beyond the existing
# on-disk/non-empty check, the gate must FAIL when a referenced evidence/ path is
# present on disk but NOT git-tracked (untracked/uncommitted) — the failure mode
# that let INV-SYNTH-01 push findings without their 69 evidence files.
# Local run (no network): execute with the sandbox disabled.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; GATE="$HERE/verify-register.sh"
fail=0
ok(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m❌\033[0m %s\n' "$1"; fail=1; }

# Throwaway git workspace with the dossier register layout. Needs a writable temp dir
# and a working `git init`; a restrictive sandbox blocks both — skip cleanly rather than
# scan the real repo and report a misleading red.
skip(){ printf '  \033[33m⏭\033[0m  SKIP: %s — run with the sandbox disabled\n' "$1"; exit 77; }
WS="$(mktemp -d 2>/dev/null)" || true
{ [ -n "$WS" ] && [ -d "$WS" ]; } || skip "cannot create a temp workspace (mktemp blocked)"
trap 'rm -rf "$WS"' EXIT
git -C "$WS" init -q 2>/dev/null || skip "cannot git init the temp workspace (git blocked)"
git -C "$WS" config user.email t@t.local; git -C "$WS" config user.name tester
mkdir -p "$WS/dossier/sources" "$WS/evidence/documents"
cat > "$WS/dossier/sources/register.yaml" <<'YAML'
sources:
  - id: src-001
    origin: "evidence/documents/foo.json"
YAML
printf '{"ok":1}' > "$WS/evidence/documents/foo.json"

# (b) RED: evidence present on disk but UNTRACKED → gate must FAIL (uncommitted).
out="$(bash "$GATE" "$WS" 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "uncommitted"; } \
  && ok "present-but-untracked evidence → gate fails (uncommitted)" \
  || no "untracked evidence not caught (rc=$rc): $out"

# (a) evidence present AND git-tracked (staged counts) → gate passes.
git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qi "OK"; } \
  && ok "present + tracked evidence → gate passes" \
  || no "tracked evidence wrongly failed (rc=$rc): $out"

# (e) a source whose archive_url is a comma-joined list of several evidence paths (folded
#     YAML scalar `>-`, as INV-SYNTH-01's researchers wrote) — all present + tracked —
#     must PASS. RED before the fix: the checker treated the whole comma-joined string as one
#     filename and reported every path phantom.
cat >> "$WS/dossier/sources/register.yaml" <<'YAML'
  - id: src-002
    archive_url: >-
      evidence/documents/multi-a.png,
      evidence/documents/multi-b.png
YAML
printf 'a' > "$WS/evidence/documents/multi-a.png"
printf 'b' > "$WS/evidence/documents/multi-b.png"
git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qi "OK"; } \
  && ok "multi-path archive_url (all present + tracked) → gate passes" \
  || no "multi-path archive_url wrongly failed (rc=$rc): $out"

# (f) multi-path archive_url where ONE of the paths is missing → gate must still FAIL (phantom).
cat >> "$WS/dossier/sources/register.yaml" <<'YAML'
  - id: src-003
    archive_url: >-
      evidence/documents/multi-a.png,
      evidence/documents/ghost.png
YAML
out="$(bash "$GATE" "$WS" 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "ghost.png"; } \
  && ok "multi-path with one missing sub-path → gate fails naming the missing one" \
  || no "multi-path missing sub-path not caught (rc=$rc): $out"

# Reset to the single-source register so the remaining cases behave as before.
cat > "$WS/dossier/sources/register.yaml" <<'YAML'
sources:
  - id: src-001
    origin: "evidence/documents/foo.json"
YAML
git -C "$WS" add -A

# (c) referenced evidence MISSING on disk → gate fails (PHANTOM, existing behaviour).
rm "$WS/evidence/documents/foo.json"
out="$(bash "$GATE" "$WS" 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "phantom"; } \
  && ok "missing-on-disk evidence → gate fails (phantom)" \
  || no "missing evidence not caught (rc=$rc): $out"

# (d) no register file at all → gate is a clean no-op (exit 0).
WS2="$(mktemp -d)"; git -C "$WS2" init -q
out="$(bash "$GATE" "$WS2" 2>&1)"; rc=$?
rm -rf "$WS2"
{ [ "$rc" -eq 0 ]; } && ok "no register → clean no-op" || no "empty register mishandled (rc=$rc): $out"

exit "$fail"
