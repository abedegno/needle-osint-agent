#!/usr/bin/env bash
# Runner-executed test for companies-house.sh. Run via:
#   ./omnigent.sh exec "cd /workspaces/<your-workspace> && omnigent/tests/test-companies-house.sh"
# Offline via a PATH-shimmed curl (same pattern as test-ch-imaged.sh / test-ch-batch.sh) — no
# live COMPANIES_HOUSE_API_KEY or network required; both paths run deterministically.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; BIN="$HERE/../bin/companies-house.sh"
fail=0
ok(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m❌\033[0m %s\n' "$1"; fail=1; }
skip(){ printf '  \033[33m⏭\033[0m  SKIP: %s — run with the sandbox disabled\n' "$1"; exit 77; }

for t in mktemp jq; do command -v "$t" >/dev/null 2>&1 || skip "missing '$t'"; done
WS="$(mktemp -d 2>/dev/null)" || true
{ [ -n "$WS" ] && [ -d "$WS" ]; } || skip "cannot create a temp workspace (mktemp blocked)"
trap 'rm -rf "$WS"' EXIT

# Failure path: blank key -> reg_require_key dies before any network call, so this needs no shim.
out="$(COMPANIES_HOUSE_API_KEY="" REG_EVIDENCE_DIR="$WS/ev" bash "$BIN" profile 00000000 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "COMPANIES_HOUSE_API_KEY is empty"; then
  ok "blank key → fails loud"
else
  no "blank key did not fail correctly (rc=$rc): $out"
fi

# Fake curl shim: reg_get calls `curl ... -u KEY: <url> -D <hdr> -o <tmp> -w '%{http_code}'`.
# Serve a synthetic company profile for every request. Anchor: company 00000000 =
# EXAMPLE TRADING LTD (synthetic fixture).
mkdir -p "$WS/bin"
cat > "$WS/bin/curl" <<'CURL'
#!/usr/bin/env bash
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
if [ -n "$out" ]; then
  cat > "$out" <<'JSON'
{"company_number":"00000000","company_name":"EXAMPLE TRADING LTD","company_status":"active"}
JSON
fi
printf '200'
CURL
chmod +x "$WS/bin/curl"
export PATH="$WS/bin:$PATH"

# Happy path: shimmed key + shimmed curl -> deterministic PASS, no live network/key needed.
out="$(COMPANIES_HOUSE_API_KEY=testkey REG_EVIDENCE_DIR="$WS/ev" bash "$BIN" profile 00000000 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qi "EXAMPLE TRADING LTD"; then
  ok "profile 00000000 → EXAMPLE TRADING LTD, archived"
else
  no "happy-path failed (rc=$rc): $out"
fi

exit "$fail"
