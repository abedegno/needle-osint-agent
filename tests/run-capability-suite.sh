#!/usr/bin/env bash
# run-capability-suite.sh — one ✅/❌ roll-up of the capability + regression checks.
# Run ON THE RUNNER (the live checks need LAN + keys):
#   ./omnigent.sh exec "cd /workspaces/<your-workspace> && bash omnigent/tests/run-capability-suite.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
fail=0
run(){ # run <label> <script-path>
  printf '\n=== %s ===\n' "$1"
  if bash "$2"; then printf '  \033[32mPASS\033[0m %s\n' "$1"; else printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=1; fi
}
run "harness-selftest (env cases)" "$HERE/test-harness-selftest.sh"
run "verify-register integrity"    "$HERE/test-verify-register.sh"
run "crawl4ai auth (VT-4)"         "$HERE/verify-crawl4ai-auth.sh"
run "companies-house API"          "$HERE/test-companies-house.sh"
printf '\n'
if [ "$fail" -eq 0 ]; then printf '\033[32mSUITE: ALL PASS\033[0m\n'; else printf '\033[31mSUITE: FAILURES\033[0m\n'; fi
exit "$fail"
