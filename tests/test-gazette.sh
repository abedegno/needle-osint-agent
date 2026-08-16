#!/usr/bin/env bash
# Runner/local test for gazette.sh. Local run (network): execute with the sandbox disabled.
# Runner run: ./omnigent.sh exec "cd /workspaces/<your-workspace> && omnigent/tests/test-gazette.sh"
# Keyless API → happy-path always runs.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; BIN="$HERE/../bin/gazette.sh"
TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
fail=0
ok(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m❌\033[0m %s\n' "$1"; fail=1; }

# Failure-path (offline): too few args → usage die, non-zero.
out="$(REG_EVIDENCE_DIR="$TMPD" bash "$BIN" search 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && echo "$out" | grep -qi "usage"; } && ok "bad args → usage die" || no "bad args not handled (rc=$rc): $out"

# Happy-path (live): search → f:total is a number, archived.
out="$(REG_EVIDENCE_DIR="$TMPD" bash "$BIN" search "insolvency" 2>&1)"; rc=$?
arc="$(echo "$out" | head -1 | awk '{print $1}')"
{ [ "$rc" -eq 0 ] && [ -s "$arc" ] && jq -e '.["f:total"]|tonumber|type=="number"' "$arc" >/dev/null 2>&1; } \
  && ok "search → f:total number, archived" || no "search failed (rc=$rc): $out"

# Happy-path (live): a nonsense term → 0 results is still a SUCCESS (not a failure).
out="$(REG_EVIDENCE_DIR="$TMPD" bash "$BIN" search "Zzqxvwqq" 2>&1)"; rc=$?
arc="$(echo "$out" | head -1 | awk '{print $1}')"
{ [ "$rc" -eq 0 ] && jq -e '(.["f:total"]|tonumber)==0' "$arc" >/dev/null 2>&1; } \
  && ok "zero-results term → clean success (f:total=0)" || no "zero-results mishandled (rc=$rc): $out"

# Default output (no --jq) is the tidy normalized view: line 2+ parses as {total, notices:[...]}.
norm="$(REG_EVIDENCE_DIR="$TMPD" bash "$BIN" search "insolvency" 2>/dev/null | tail -n +2)"
{ printf '%s' "$norm" | jq -e '(.total|type=="number") and (.notices|type=="array") and (.notices[0]|has("code") and has("title") and has("date") and has("link"))' >/dev/null 2>&1; } \
  && ok "default stdout → normalized {total,notices[{code,title,date,link}]}" || no "normalized default output malformed: $(printf '%s' "$norm" | head -c 120)"

# --jq override still bypasses the normalizer (raw-body query).
ovr="$(REG_EVIDENCE_DIR="$TMPD" bash "$BIN" --jq '.["f:total"]' search "insolvency" 2>/dev/null | tail -n +2)"
{ printf '%s' "$ovr" | jq -e 'type=="string" or type=="number"' >/dev/null 2>&1; } \
  && ok "--jq override → raw-body query (not normalized)" || no "--jq override failed: $ovr"

exit "$fail"
