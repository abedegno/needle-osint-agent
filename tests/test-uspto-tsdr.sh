#!/usr/bin/env bash
# Runner-executed test for uspto-tsdr.sh. Run via:
#   ./omnigent.sh exec "cd /workspaces/<your-workspace> && omnigent/tests/test-uspto-tsdr.sh"
# Failure-path always runs. Happy-path needs USPTO_API_KEY + USPTO_TEST_SERIAL (a real USPTO
# serial/registration number from your own investigation's USPTO sources) — skips with ⚠️ if absent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; BIN="$HERE/../bin/uspto-tsdr.sh"
fail=0
skip(){ printf '  \033[33m⏭\033[0m  SKIP: %s — run with the sandbox disabled\n' "$1"; exit 77; }
command -v mktemp >/dev/null 2>&1 || skip "missing 'mktemp'"
TMPD="$(mktemp -d 2>/dev/null)" || skip "mktemp blocked"
{ [ -n "$TMPD" ] && [ -d "$TMPD" ]; } || skip "cannot create a temp workspace (mktemp blocked)"
trap 'rm -rf "$TMPD"' EXIT

out="$(USPTO_API_KEY="" REG_EVIDENCE_DIR="$TMPD" bash "$BIN" status 88888888 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "USPTO_API_KEY is empty"; then
  printf '  \033[32m✅\033[0m blank key → fails loud\n'
else
  printf '  \033[31m❌\033[0m blank key did not fail correctly (rc=%s): %s\n' "$rc" "$out"; fail=1
fi

if [ -z "${USPTO_API_KEY:-}" ] || [ -z "${USPTO_TEST_SERIAL:-}" ]; then
  printf '  \033[33m⚠️\033[0m  USPTO_API_KEY/USPTO_TEST_SERIAL not set — skipping happy-path\n'
else
  out="$(REG_EVIDENCE_DIR="$TMPD" bash "$BIN" status "$USPTO_TEST_SERIAL" 2>&1)"; rc=$?
  arc="$(echo "$out" | head -1 | awk '{print $1}')"
  if [ "$rc" -eq 0 ] && [ -s "$arc" ] && jq -e 'type=="object"' "$arc" >/dev/null 2>&1; then
    printf '  \033[32m✅\033[0m status %s → archived valid JSON object\n' "$USPTO_TEST_SERIAL"
  else
    printf '  \033[31m❌\033[0m happy-path failed (rc=%s): %s\n' "$rc" "$out"; fail=1
  fi
fi
exit "$fail"
