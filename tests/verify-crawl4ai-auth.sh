#!/usr/bin/env bash
# VT-4: crawl4ai 0.9.0 auth wiring. Run ON THE RUNNER (it can reach the crawl4ai
# host and carries CRAWL4AI_API_TOKEN in its env):
#   ./omnigent.sh exec "cd /workspaces/<your-workspace> && omnigent/tests/verify-crawl4ai-auth.sh"
# Needs no investigation session — this is an infrastructure check.
set -uo pipefail
HOST="${CRAWL4AI_HOST:-http://localhost:11235}"
body='{"url":"https://example.com"}'
fail=0

echo "VT-4 crawl4ai auth @ $HOST"

# Unauthenticated → expect 401 (proves auth is ON, the secure-by-default 0.9.0 posture).
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HOST/screenshot" \
  -H 'Content-Type: application/json' -d "$body" || echo "000")
if [ "$code" = "401" ]; then
  printf '  \033[32m✅\033[0m unauthenticated → 401 (auth is ON)\n'
else
  printf '  \033[31m❌\033[0m unauthenticated → %s (expected 401)\n' "$code"; fail=1
fi

# Authenticated → expect success + an inline base64 screenshot string.
if [ -z "${CRAWL4AI_API_TOKEN:-}" ]; then
  printf '  \033[33m⚠️\033[0m  CRAWL4AI_API_TOKEN not in env — skipping authed check\n'
else
  resp=$(curl -s -X POST "$HOST/screenshot" \
    -H "Authorization: Bearer $CRAWL4AI_API_TOKEN" \
    -H 'Content-Type: application/json' -d "$body" || echo '{}')
  if echo "$resp" | jq -e '.success == true and (.screenshot | type == "string")' >/dev/null 2>&1; then
    printf '  \033[32m✅\033[0m authenticated → success + inline base64 screenshot\n'
  else
    printf '  \033[31m❌\033[0m authenticated call returned no screenshot\n'
    echo "$resp" | head -c 200; echo; fail=1
  fi
fi

exit "$fail"
