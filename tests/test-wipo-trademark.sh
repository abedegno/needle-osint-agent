#!/usr/bin/env bash
# Test for wipo-trademark.sh. Arg-validation cases run offline (validation precedes any network).
# The decrypt engine is covered by test-wipo-decrypt.js; a live end-to-end smoke is opt-in (WIPO_LIVE=1,
# needs network + hits the rate-limited captcha).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SH="$HERE/../bin/wipo-trademark.sh"
fail=0
ok(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m❌\033[0m %s\n' "$1"; fail=1; }

# (a) offline decrypt engine fixture (deterministic, no network)
if command -v node >/dev/null 2>&1; then
  out="$(node "$HERE/test-wipo-decrypt.js" 2>&1)"; rc=$?
  { [ "$rc" = 0 ] && printf '%s' "$out" | grep -q "decrypt fixture OK"; } \
    && ok "decrypt engine reproduces the fixture" || no "decrypt fixture (rc=$rc): $out"
else
  printf '  \033[33m⏭\033[0m  SKIP decrypt fixture — node missing\n'
fi

# (b) bad mode → usage/validation error (offline)
out="$(bash "$SH" bogus query 2>&1)"; rc=$?
{ [ "$rc" != 0 ] && printf '%s' "$out" | grep -qi "mode must be"; } \
  && ok "bad mode → validation error" || no "bad-mode (rc=$rc): $out"

# (c) too few args → usage error (offline)
out="$(bash "$SH" owner 2>&1)"; rc=$?
{ [ "$rc" != 0 ] && printf '%s' "$out" | grep -qi "usage:"; } \
  && ok "missing query → usage error" || no "usage (rc=$rc): $out"

# (d) opt-in live smoke
if [ "${WIPO_LIVE:-0}" = "1" ]; then
  out="$(cd "$HERE/.." && bash bin/wipo-trademark.sh brand "EXAMPLE BRAND" 2>&1)"; rc=$?
  { [ "$rc" = 0 ] && printf '%s' "$out" | grep -qi "marks for brand:EXAMPLE BRAND"; } \
    && ok "LIVE: brand search returns marks" || no "LIVE (rc=$rc): $out"
else
  printf '  \033[33m⏭\033[0m  live smoke skipped (set WIPO_LIVE=1 to run)\n'
fi

exit "$fail"
