#!/usr/bin/env bash
# companies-house-imaged.sh — fetch ONE Companies House imaged-document PDF (Document API),
# OCR it (pdftoppm + tesseract), and print a ready-to-append register.yaml block. Never writes
# register.yaml (the coordinator pastes the block). Binary-safe: writes the PDF directly with
# curl -o (reg_archive is JSON-string only). /document/{id}/content 302-redirects to a signed S3
# URL → curl -L (Basic auth on the first hop only).
# Usage: companies-house-imaged.sh [--company NO] [--form TYPE] [--filed YYYY-MM-DD] <doc_id|metadata_url> <out.pdf>
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/_registry-lib.sh"
DOCBASE="https://document-api.company-information.service.gov.uk"

COMPANY=""; FORM=""; FILED=""; ARGS=()
while [ $# -gt 0 ]; do case "$1" in
  --company) COMPANY="${2:-}"; shift 2 ;;
  --form)    FORM="${2:-}"; shift 2 ;;
  --filed)   FILED="${2:-}"; shift 2 ;;
  *) ARGS+=("$1"); shift ;;
esac; done
[ "${#ARGS[@]}" -eq 2 ] || die "usage: companies-house-imaged.sh [--company NO] [--form TYPE] [--filed DATE] <doc_id|metadata_url> <out.pdf>"
RAW="${ARGS[0]}"; OUT="${ARGS[1]}"
case "$OUT" in *.pdf) ;; *) die "output path must end in .pdf (got: $OUT)" ;; esac

# Resolve doc id: strip a trailing /content, then take the last path segment.
DOC="${RAW%/content}"; DOC="${DOC##*/}"
[ -n "$DOC" ] || die "could not resolve a document id from: $RAW"

reg_require_key COMPANIES_HOUSE_API_KEY "register free at developer.company-information.service.gov.uk"
mkdir -p "$(dirname "$OUT")" || die "cannot create output dir for $OUT"

# Fetch the PDF with one 429 retry. HTTP is global (no `local`), visible after the call.
fetch_pdf(){
  HTTP="$(curl -sS -L -u "$COMPANIES_HOUSE_API_KEY:" -H 'Accept: application/pdf' \
    -o "$OUT" -w '%{http_code}' "$DOCBASE/document/$DOC/content")"; local rc=$?
  if [ "$rc" -eq 0 ] && [ "$HTTP" = "429" ]; then
    sleep 2
    HTTP="$(curl -sS -L -u "$COMPANIES_HOUSE_API_KEY:" -H 'Accept: application/pdf' \
      -o "$OUT" -w '%{http_code}' "$DOCBASE/document/$DOC/content")"; rc=$?
  fi
  return $rc
}
fetch_pdf; rc=$?
[ "$rc" -eq 0 ] || die "CH document fetch failed (curl exit $rc) for $DOC"
case "$HTTP" in 2??) ;; *) die "CH document http $HTTP for $DOC" ;; esac
[ -s "$OUT" ] || die "fetched document is empty: $DOC"
SZ="$(wc -c < "$OUT" | tr -d ' ')"; [ "$SZ" -gt 1024 ] || die "document too small (${SZ}B) for $DOC"
file "$OUT" | grep -q "PDF document" || die "fetched document is not a PDF: $(file -b "$OUT")"
PDF_SHA="$(sha256sum "$OUT" | cut -d' ' -f1)"

# OCR (non-fatal). pdftoppm rasterizes each page; tesseract OCRs each PNG.
TXT="${OUT%.pdf}.txt"; OCR_OK=1
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if command -v pdftoppm >/dev/null 2>&1 && command -v tesseract >/dev/null 2>&1 \
   && pdftoppm -png -r 150 "$OUT" "$TMP/page" 2>/dev/null; then
  : > "$TXT"
  for p in "$TMP"/page-*.png; do [ -e "$p" ] || continue; tesseract "$p" stdout 2>/dev/null >> "$TXT"; done
  [ -s "$TXT" ] || { rm -f "$TXT"; OCR_OK=0; }
else
  OCR_OK=0
fi
PAGES="$(ls "$TMP"/page-*.png 2>/dev/null | wc -l | tr -d ' ')"

# Emit the register block (stdout) + a one-line summary (stderr).
RETRIEVED="$(date -u +%Y-%m-%d)"
{
  echo "- id: src-TODO-1"
  echo "  origin: $DOCBASE/document/$DOC/content"
  [ -n "$COMPANY" ] && echo "  company: \"$COMPANY\""
  [ -n "$FORM" ]    && echo "  form_type: $FORM"
  [ -n "$FILED" ]   && echo "  filed_date: $FILED"
  echo "  evidence: $OUT"
  echo "  sha256: $PDF_SHA"
  if [ "$OCR_OK" -eq 1 ]; then echo "  companion_ocr: $TXT"; else echo "  companion_ocr: (OCR failed)"; fi
  echo "  retrieved: $RETRIEVED"
}
echo "$OUT $PDF_SHA pages=$PAGES ocr=$([ "$OCR_OK" -eq 1 ] && echo ok || echo failed)" >&2
exit 0
