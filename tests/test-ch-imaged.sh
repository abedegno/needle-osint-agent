#!/usr/bin/env bash
# Test for companies-house-imaged.sh — fetch a CH imaged PDF (Document API, curl-shimmed),
# OCR it, and print a register block. Run with the sandbox disabled (needs a writable tmp dir).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SCRIPT="$HERE/../bin/companies-house-imaged.sh"
fail=0
ok(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m❌\033[0m %s\n' "$1"; fail=1; }
skip(){ printf '  \033[33m⏭\033[0m  SKIP: %s — run with the sandbox disabled\n' "$1"; exit 77; }

for t in mktemp jq file sha256sum wc python3; do command -v "$t" >/dev/null 2>&1 || skip "missing '$t'"; done
WS="$(mktemp -d 2>/dev/null)" || true
{ [ -n "$WS" ] && [ -d "$WS" ]; } || skip "cannot create a temp workspace (mktemp blocked)"
trap 'rm -rf "$WS"' EXIT

# Fake curl shim: behaviour by $FAKE_CH_MODE. Parses -o <file>. success → write a minimal valid
# PDF (>1KB) + print 200; notfound → print 404 + empty body.
mkdir -p "$WS/bin"
cat > "$WS/bin/curl" <<'CURL'
#!/usr/bin/env bash
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
case "$FAKE_CH_MODE" in
  notfound) printf '404' ;;
  *)
    if [ -n "$out" ]; then
      { printf '%%PDF-1.1\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
        printf '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
        printf '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\n'
        printf 'trailer<</Size 4/Root 1 0 R>>\nstartxref\n0\n%%%%EOF\n'
        head -c 1200 /dev/zero | tr '\0' '%'
      } > "$out"
    fi
    printf '200' ;;
esac
CURL
chmod +x "$WS/bin/curl"
export PATH="$WS/bin:$PATH"
export COMPANIES_HOUSE_API_KEY=testkey

# (a) success → register block with the expected fields + the PDF on disk. Anchor: company
# 00000000 = EXAMPLE TRADING LTD (synthetic fixture); AP01 kept as a generic CH form type.
out="$(FAKE_CH_MODE=success bash "$SCRIPT" --company 00000000 --form AP01 --filed 2020-01-01 \
        qMP5P8dJiOnh-doc "$WS/d.pdf" 2>"$WS/err")"; rc=$?
{ [ "$rc" = 0 ] \
  && printf '%s' "$out" | grep -q 'origin: https://document-api.company-information.service.gov.uk/document/qMP5P8dJiOnh-doc/content' \
  && printf '%s' "$out" | grep -Eq 'sha256: [0-9a-f]{64}' \
  && printf '%s' "$out" | grep -q 'company: "00000000"' \
  && printf '%s' "$out" | grep -q 'form_type: AP01' \
  && printf '%s' "$out" | grep -q 'companion_ocr:' \
  && printf '%s' "$out" | grep -q "evidence: $WS/d.pdf" \
  && [ -f "$WS/d.pdf" ] && file "$WS/d.pdf" | grep -q 'PDF document'; } \
  && ok "success → register block + PDF on disk" || no "success (rc=$rc): out='$out' err='$(cat "$WS/err")'"

# (b) doc-id resolution: full …/content URL → origin uses the bare id
out="$(FAKE_CH_MODE=success bash "$SCRIPT" \
        "https://document-api.company-information.service.gov.uk/document/abc123/content" "$WS/e.pdf" 2>/dev/null)"
printf '%s' "$out" | grep -q 'document/abc123/content' \
  && ok "metadata-URL with /content → id resolved" || no "id resolution: $out"

# (c) HTTP 404 → die names the status
FAKE_CH_MODE=notfound bash "$SCRIPT" zz "$WS/f.pdf" 2>"$WS/err"; rc=$?
{ [ "$rc" != 0 ] && grep -qi "http 404" "$WS/err"; } \
  && ok "404 → reports http status" || no "404 case (rc=$rc): $(cat "$WS/err")"

# (d) bad extension → validation error
FAKE_CH_MODE=success bash "$SCRIPT" zz "$WS/g.txt" 2>"$WS/err"; rc=$?
{ [ "$rc" != 0 ] && grep -qi "must end in .pdf" "$WS/err"; } \
  && ok "non-.pdf output → validation error" || no "bad-ext case (rc=$rc): $(cat "$WS/err")"

exit "$fail"
