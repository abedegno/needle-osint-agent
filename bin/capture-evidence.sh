#!/usr/bin/env bash
# capture-evidence.sh — capture a web page as a screenshot (.png) or page-PDF (.pdf), landing the
# bytes on the runner filesystem. The ONLY sanctioned evidence-capture path.
#   default     crawl4ai REST (/screenshot|/pdf -> /artifacts) — reliable archival.
#   --stealth   direct CloakBrowser via capture-stealth.py — fingerprint/webdriver-walled pages (PNG only).
# Do NOT use the crawl4ai MCP screenshot/pdf tools: they write to the crawl4ai container's own fs
# (inaccessible to the runner) and report false success.
# Usage: capture-evidence.sh [--stealth] <url> <output-path.(png|pdf)>
set -uo pipefail
CRAWL4AI_HOST="${CRAWL4AI_HOST:-http://localhost:11235}"
OUT=""; STEALTH=0
die(){ echo "capture-evidence: ERROR: $*" >&2; [ -n "$OUT" ] && rm -f "$OUT"; exit 1; }

# First ~200 chars of a response body on one line, for diagnostics. Empty -> "(empty body)".
_snippet(){ [ -s "$1" ] || { echo "(empty body)"; return; }; tr '\n' ' ' < "$1" | cut -c1-200 | sed 's/[[:space:]]\{1,\}/ /g'; }

ARGS=()
for a in "$@"; do
  if [ "$a" = "--stealth" ]; then STEALTH=1; else ARGS+=("$a"); fi
done
[ "${#ARGS[@]}" -eq 2 ] || die "usage: capture-evidence.sh [--stealth] <url> <output-path.(png|pdf)>"
URL="${ARGS[0]}"; OUT="${ARGS[1]}"
case "$OUT" in
  *.png) MODE="screenshot"; MAGIC="PNG image data" ;;
  *.pdf) MODE="pdf";        MAGIC="PDF document"   ;;
  *) die "output path must end in .png or .pdf (got: $OUT)" ;;
esac
mkdir -p "$(dirname "$OUT")" || die "cannot create output dir for $OUT"

if [ "$STEALTH" -eq 1 ]; then
  [ "$MODE" = "screenshot" ] || die "--stealth supports .png only (page-PDF uses the default track)"
  HERE="$(cd "$(dirname "$0")" && pwd)"
  [ -f "$HERE/capture-stealth.py" ] || die "stealth track not yet installed (capture-stealth.py missing)"
  python3 "$HERE/capture-stealth.py" "$URL" "$OUT" || die "stealth capture failed for $URL"
else
  [ -n "${CRAWL4AI_API_TOKEN:-}" ] || die "CRAWL4AI_API_TOKEN is empty in this shell"
  AUTH="Authorization: Bearer $CRAWL4AI_API_TOKEN"
  TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
  BODY="$(jq -n --arg u "$URL" '{url: $u}')"
  HTTP="$(curl -s -m 90 -w '%{http_code}' -o "$TMP" -X POST "$CRAWL4AI_HOST/$MODE" \
    -H "$AUTH" -H 'Content-Type: application/json' -d "$BODY")"; rc=$?
  [ "$rc" -eq 0 ] || die "crawl4ai /$MODE POST failed (curl exit $rc — timeout/connection) for $URL"
  case "$HTTP" in 2??) ;; *) die "crawl4ai /$MODE POST http $HTTP for $URL: $(_snippet "$TMP")" ;; esac
  AID="$(jq -r '.artifact_id // empty' "$TMP" 2>/dev/null)"
  [ -n "$AID" ] || die "crawl4ai /$MODE returned no artifact (http $HTTP; $(_snippet "$TMP")) for $URL"
  CODE="$(curl -s -m 90 -H "$AUTH" "$CRAWL4AI_HOST/artifacts/$AID" -o "$OUT" -w '%{http_code}')"
  [ "$CODE" = "200" ] || die "artifact fetch failed (http $CODE) for $URL"
fi

[ -s "$OUT" ] || die "captured file is empty: $OUT"
SZ="$(wc -c < "$OUT" | tr -d ' ')"
[ "$SZ" -gt 1024 ] || die "captured file too small (${SZ}B, <1KB): $OUT"
file "$OUT" | grep -q "$MAGIC" || die "captured file is not a $MAGIC: $(file -b "$OUT")"
echo "$OUT $SZ $(sha256sum "$OUT" | cut -d' ' -f1)"
