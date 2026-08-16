#!/usr/bin/env bash
# Tests harness-selftest.sh. The env-presence cases run anywhere (they abort before any
# live call); live checks are runner-only and not asserted here.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SELF="$HERE/../bin/harness-selftest.sh"
fail=0
ok(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
bad(){ printf '  \033[31m❌\033[0m %s\n' "$1"; fail=1; }

# CRAWL4AI_API_TOKEN unset (CH key present) → non-zero + MISSING names the token, before any live check.
out="$(env -u CRAWL4AI_API_TOKEN COMPANIES_HOUSE_API_KEY=dummy bash "$SELF" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "unset CRAWL4AI_API_TOKEN → non-zero exit" || bad "unset token still exited 0"
printf '%s' "$out" | grep -q "MISSING:.*CRAWL4AI_API_TOKEN" && ok "names CRAWL4AI_API_TOKEN as MISSING" || bad "did not name CRAWL4AI_API_TOKEN as MISSING"

# COMPANIES_HOUSE_API_KEY unset (token present) → non-zero + MISSING names the CH key.
out="$(env -u COMPANIES_HOUSE_API_KEY CRAWL4AI_API_TOKEN=dummy bash "$SELF" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "unset COMPANIES_HOUSE_API_KEY → non-zero exit" || bad "unset CH key still exited 0"
printf '%s' "$out" | grep -q "MISSING:.*COMPANIES_HOUSE_API_KEY" && ok "names COMPANIES_HOUSE_API_KEY as MISSING" || bad "did not name CH key as MISSING"

exit "$fail"
