#!/usr/bin/env bash
# harness-selftest.sh — runs INSIDE an agent-harness shell and checks the tool/auth
# environment THAT harness actually has (the codex-native verifier shell differs from the
# claude-sdk researcher's — see the runner env-passthrough notes). Read-only. Exit 0 = healthy, non-zero = degraded.
# Env-presence is checked first and aborts before any live call; live checks retry to absorb blips.
set -uo pipefail
CRAWL4AI_HOST="${CRAWL4AI_HOST:-http://localhost:11235}"
SEARXNG_URL="${SEARXNG_URL:-http://localhost:8080}"
ok(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
bad(){ printf '  \033[31m❌\033[0m %s\n' "$1"; }

echo "HARNESS SELFTEST ($(uname -n 2>/dev/null || echo '?'))"

# --- Stage 1: env-presence (abort before live if any required key is empty) ---
miss=()
if [ -n "${CRAWL4AI_API_TOKEN:-}" ]; then ok "CRAWL4AI_API_TOKEN present"; else bad "CRAWL4AI_API_TOKEN empty"; miss+=("CRAWL4AI_API_TOKEN"); fi
if [ -n "${COMPANIES_HOUSE_API_KEY:-}" ]; then ok "COMPANIES_HOUSE_API_KEY present"; else bad "COMPANIES_HOUSE_API_KEY empty"; miss+=("COMPANIES_HOUSE_API_KEY"); fi
if [ "${#miss[@]}" -gt 0 ]; then
  echo "RESULT: FAIL (${#miss[@]} problems)"
  echo "MISSING: ${miss[*]}"
  exit 1
fi

# --- Stage 2: live checks (retry to absorb transient blips) ---
problems=()
retry(){ # retry <n> <desc> <cmd...>
  local n="$1" desc="$2"; shift 2; local i
  for (( i = 0; i < n; i++ )); do
    if "$@" >/dev/null 2>&1; then ok "$desc"; return 0; fi
    (( i < n - 1 )) && sleep 2   # back off between attempts, not after the last
  done
  bad "$desc (failed ${n}x)"; problems+=("$desc"); return 1
}
chk_crawl4ai(){ curl -fsS -X POST "$CRAWL4AI_HOST/screenshot" -H "Authorization: Bearer $CRAWL4AI_API_TOKEN" -H 'Content-Type: application/json' -d '{"url":"https://example.com"}' | jq -e '.success==true'; }
chk_ch(){ curl -fsS -u "$COMPANIES_HOUSE_API_KEY:" "https://api.company-information.service.gov.uk/search/companies?q=test&items_per_page=1" | jq -e '.items'; }
chk_searxng(){ curl -fsS "$SEARXNG_URL/search?q=test&format=json" | jq -e '.results | length > 0'; }

retry 3 "crawl4ai authed call" chk_crawl4ai
retry 2 "companies-house lookup" chk_ch
retry 3 "searxng query" chk_searxng

if [ "${#problems[@]}" -gt 0 ]; then
  echo "RESULT: FAIL (${#problems[@]} problems)"
  echo "FAILED: ${problems[*]}"
  exit 1
fi
echo "RESULT: PASS"
exit 0
