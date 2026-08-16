#!/usr/bin/env bash
# Runner-executed test for courtlistener.sh. Run via:
#   ./omnigent.sh exec "cd /workspaces/<your-workspace> && omnigent/tests/test-courtlistener.sh"
# Failure-path always runs; happy-path needs COURTLISTENER_TOKEN (skips with ⚠️ if absent).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; BIN="$HERE/../bin/courtlistener.sh"
fail=0
skip(){ printf '  \033[33m⏭\033[0m  SKIP: %s — run with the sandbox disabled\n' "$1"; exit 77; }
command -v mktemp >/dev/null 2>&1 || skip "missing 'mktemp'"
TMPD="$(mktemp -d 2>/dev/null)" || skip "mktemp blocked"
{ [ -n "$TMPD" ] && [ -d "$TMPD" ]; } || skip "cannot create a temp workspace (mktemp blocked)"
trap 'rm -rf "$TMPD"' EXIT

out="$(COURTLISTENER_TOKEN="" REG_EVIDENCE_DIR="$TMPD" bash "$BIN" search "example corp" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "COURTLISTENER_TOKEN is empty"; then
  printf '  \033[32m✅\033[0m blank token → fails loud\n'
else
  printf '  \033[31m❌\033[0m blank token did not fail correctly (rc=%s): %s\n' "$rc" "$out"; fail=1
fi

if [ -z "${COURTLISTENER_TOKEN:-}" ]; then
  printf '  \033[33m⚠️\033[0m  COURTLISTENER_TOKEN not set — skipping happy-path\n'
else
  out="$(REG_EVIDENCE_DIR="$TMPD" bash "$BIN" search "example corp" 2>&1)"; rc=$?
  arc="$(echo "$out" | head -1 | awk '{print $1}')"
  if [ "$rc" -eq 0 ] && [ -s "$arc" ] && jq -e '.results | type=="array"' "$arc" >/dev/null 2>&1; then
    printf '  \033[32m✅\033[0m search → results array, archived\n'
  else
    printf '  \033[31m❌\033[0m happy-path failed (rc=%s): %s\n' "$rc" "$out"; fail=1
  fi
fi
exit "$fail"
