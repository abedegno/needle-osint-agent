#!/usr/bin/env bash
# Runner/local test for gleif.sh. Local run (network): execute with the sandbox disabled.
# Runner run: ./omnigent.sh exec "cd /workspaces/<your-workspace> && omnigent/tests/test-gleif.sh"
# Keyless API → happy-path always runs. Apple Inc LEI HWUPKR0MPOU8FGXBT394 is the live fixture.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; BIN="$HERE/../bin/gleif.sh"
TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
LEI="HWUPKR0MPOU8FGXBT394"
fail=0
ok(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m❌\033[0m %s\n' "$1"; fail=1; }

# Failure-path (offline): too few args → usage die, non-zero.
out="$(REG_EVIDENCE_DIR="$TMPD" bash "$BIN" search 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && echo "$out" | grep -qi "usage"; } && ok "bad args → usage die" || no "bad args not handled (rc=$rc): $out"

# Happy-path (live): search → data array archived.
out="$(REG_EVIDENCE_DIR="$TMPD" bash "$BIN" search "Apple Inc" 2>&1)"; rc=$?
arc="$(echo "$out" | head -1 | awk '{print $1}')"
{ [ "$rc" -eq 0 ] && [ -s "$arc" ] && jq -e '.data|type=="array"' "$arc" >/dev/null 2>&1; } \
  && ok "search → data array, archived" || no "search failed (rc=$rc): $out"

# Happy-path (live): record → exact LEI in .data.id.
out="$(REG_EVIDENCE_DIR="$TMPD" bash "$BIN" record "$LEI" 2>&1)"; rc=$?
arc="$(echo "$out" | head -1 | awk '{print $1}')"
{ [ "$rc" -eq 0 ] && jq -e --arg l "$LEI" '.data.id==$l' "$arc" >/dev/null 2>&1; } \
  && ok "record → .data.id matches" || no "record failed (rc=$rc): $out"

# Happy-path (live): parent → 404-as-empty success (Apple Inc is an ultimate parent).
out="$(REG_EVIDENCE_DIR="$TMPD" bash "$BIN" parent "$LEI" 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && echo "$out" | grep -qi "no direct parent"; } \
  && ok "parent 404 → clean empty success" || no "parent 404 mishandled (rc=$rc): $out"

# Happy-path (live): children → data array archived (Apple has children).
out="$(REG_EVIDENCE_DIR="$TMPD" bash "$BIN" children "$LEI" 2>&1)"; rc=$?
arc="$(echo "$out" | head -1 | awk '{print $1}')"
{ [ "$rc" -eq 0 ] && [ -s "$arc" ] && jq -e '.data|type=="array"' "$arc" >/dev/null 2>&1; } \
  && ok "children → data array, archived" || no "children failed (rc=$rc): $out"

exit "$fail"
