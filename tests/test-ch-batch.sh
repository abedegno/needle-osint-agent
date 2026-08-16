#!/usr/bin/env bash
# Test for ch-batch-filings.sh — filing-history filter + orchestration. curl is shimmed for the
# filing-history fetch; the imaged primitive is stubbed via $CH_IMAGED. Run sandbox-disabled.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SCRIPT="$HERE/../bin/ch-batch-filings.sh"
fail=0
ok(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m❌\033[0m %s\n' "$1"; fail=1; }
skip(){ printf '  \033[33m⏭\033[0m  SKIP: %s — run with the sandbox disabled\n' "$1"; exit 77; }

for t in mktemp jq; do command -v "$t" >/dev/null 2>&1 || skip "missing '$t'"; done
WS="$(mktemp -d 2>/dev/null)" || true
{ [ -n "$WS" ] && [ -d "$WS" ]; } || skip "cannot create a temp workspace (mktemp blocked)"
trap 'rm -rf "$WS"' EXIT

# Shim curl: reg_get invokes `curl ... -o "$tmp" -w '%{http_code}'` (body → -o file, code → stdout).
# So the shim must write the filing-history JSON to the -o target and print only the http code.
mkdir -p "$WS/bin"
cat > "$WS/bin/curl" <<'CURL'
#!/usr/bin/env bash
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat > "${out:-/dev/stdout}" <<'JSON'
{"total_count":2,"items":[
  {"type":"AP01","date":"2015-03-01","links":{"document_metadata":"https://document-api.company-information.service.gov.uk/document/doc-ap01"}},
  {"type":"CH01","date":"2012-06-01","links":{"document_metadata":"https://document-api.company-information.service.gov.uk/document/doc-ch01"}}
]}
JSON
printf '200'
CURL
chmod +x "$WS/bin/curl"
export PATH="$WS/bin:$PATH"
export COMPANIES_HOUSE_API_KEY=testkey

# Stub the primitive: echo a register block built from its flags; record that it was called.
cat > "$WS/imaged.sh" <<'IMG'
#!/usr/bin/env bash
company=""; form=""; filed=""; args=()
while [ $# -gt 0 ]; do case "$1" in
  --company) company="$2"; shift 2;; --form) form="$2"; shift 2;; --filed) filed="$2"; shift 2;;
  *) args+=("$1"); shift;; esac; done
echo "- id: src-TODO-1"
echo "  company: \"$company\""
echo "  form_type: $form"
echo "  filed_date: $filed"
echo "  evidence: ${args[1]}"
IMG
chmod +x "$WS/imaged.sh"
export CH_IMAGED="$WS/imaged.sh"

# Filter: --forms AP01 --since 2014-01-01 → only the AP01/2015 doc; CH01/2012 excluded by both.
# Anchor: company 00000000 = EXAMPLE TRADING LTD (synthetic fixture).
out="$(bash "$SCRIPT" --companies 00000000 --forms AP01 --since 2014-01-01 --out-dir "$WS/ev" 2>"$WS/err")"; rc=$?
{ [ "$rc" = 0 ] \
  && printf '%s' "$out" | grep -q 'form_type: AP01' \
  && ! printf '%s' "$out" | grep -q 'form_type: CH01' \
  && [ "$(printf '%s' "$out" | grep -c '^- id:')" = 1 ] \
  && grep -q 'summary: ok=1 ' "$WS/err"; } \
  && ok "form+date filter → only AP01 block emitted" || no "filter (rc=$rc): out='$out' err='$(cat "$WS/err")'"

# Missing --companies → usage error
bash "$SCRIPT" --forms AP01 2>"$WS/err"; rc=$?
{ [ "$rc" != 0 ] && grep -qi "companies" "$WS/err"; } \
  && ok "missing --companies → usage error" || no "usage case (rc=$rc): $(cat "$WS/err")"

exit "$fail"
