#!/usr/bin/env bash
# capture-filing-images.sh — pull full-resolution embedded court-filing photos from a source
# post (Blogger/a blog), transcribe each with the claude CLI (vision), and print a
# register.yaml block per image. Mirrors companies-house-imaged.sh: prints blocks to stdout,
# NEVER writes register.yaml. The IMAGE is the citeable evidence; the transcription is a
# labelled AI-assisted aid (non-fatal). Writes only under evidence/snapshots/<slug>/.
# Usage: capture-filing-images.sh [--model M] [--max-images N] [--timeout S] <post-url> <slug>
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
EXTRACT="$HERE/lib/extract-filing-image-urls.py"
CLAUDE_BIN="${CAPTURE_CLAUDE_BIN:-claude}"
MODEL="sonnet"; MAXIMG=20; TIMEOUT=180
OUT=""   # current image path; die() removes a half-written one
die(){ echo "capture-filing-images: ERROR: $*" >&2; [ -n "$OUT" ] && rm -f "$OUT"; exit 1; }

ARGS=()
while [ $# -gt 0 ]; do case "$1" in
  --model) [ $# -ge 2 ] || die "--model needs a value"; MODEL="$2"; shift 2 ;;
  --max-images) [ $# -ge 2 ] || die "--max-images needs a value"; MAXIMG="$2"; shift 2 ;;
  --timeout) [ $# -ge 2 ] || die "--timeout needs a value"; TIMEOUT="$2"; shift 2 ;;
  *) ARGS+=("$1"); shift ;;
esac; done
[ "${#ARGS[@]}" -eq 2 ] || die "usage: capture-filing-images.sh [--model M] [--max-images N] [--timeout S] <post-url> <slug>"
URL="${ARGS[0]}"; SLUG="${ARGS[1]}"
case "$SLUG" in */*|"") die "slug must be a simple name with no slash (got: '$SLUG')" ;; esac
command -v python3 >/dev/null 2>&1 || die "python3 not found"
[ -f "$EXTRACT" ] || die "missing helper: $EXTRACT"

DIR="evidence/snapshots/$SLUG"
mkdir -p "$DIR" || die "cannot create $DIR"

# Stage 1: fetch the post HTML, resolve full-res image URLs. Fetch to a temp file with a
# status check (mirrors companies-house-imaged.sh) so a 403/404/login-wall dies loudly instead
# of silently yielding an empty "no embedded filing images" success.
HTML_TMP="$(mktemp)"
HTTP="$(curl -sSL -m 60 -o "$HTML_TMP" -w '%{http_code}' "$URL")"; rc=$?
if [ "$rc" -ne 0 ]; then rm -f "$HTML_TMP"; die "fetch failed (curl exit $rc) for $URL"; fi
case "$HTTP" in
  2??) ;;
  *) rm -f "$HTML_TMP"; die "post fetch http $HTTP for $URL" ;;
esac
HTML="$(cat "$HTML_TMP")"; rm -f "$HTML_TMP"
[ -n "$HTML" ] || die "empty page body for $URL"
IMG_URLS=()
while IFS= read -r line; do [ -n "$line" ] && IMG_URLS+=("$line"); done \
  < <(printf '%s' "$HTML" | python3 "$EXTRACT" "$URL")
if [ "${#IMG_URLS[@]}" -eq 0 ]; then
  echo "capture-filing-images: no embedded filing images found on $URL" >&2
  exit 0
fi
if [ "${#IMG_URLS[@]}" -gt "$MAXIMG" ]; then
  echo "capture-filing-images: WARNING: ${#IMG_URLS[@]} images on $URL; capping at $MAXIMG (dropped $(( ${#IMG_URLS[@]} - MAXIMG )))" >&2
  IMG_URLS=("${IMG_URLS[@]:0:$MAXIMG}")
fi

RETRIEVED="$(date -u +%Y-%m-%d)"
CLAUDE_VER="$("$CLAUDE_BIN" --version 2>/dev/null | head -1)"; [ -n "$CLAUDE_VER" ] || CLAUDE_VER="unknown"
PROMPT='Transcribe the court document in the attached image VERBATIM. Output only the document text, preserving line and paragraph structure and the caption block. Mark unreadable text [illegible] and doubtful readings [uncertain: best-guess]. Do NOT infer, complete, or summarize anything not visibly present. If the image is not a document, output NOT A DOCUMENT and stop.'

# run_transcriber <image-path> -> prints transcription on stdout (empty on failure).
# INVOCATION CONFIRMED IN TASK 1 — adjust flags here if Task 1 found a different form.
run_transcriber(){
  local img="$1"
  command -v "$CLAUDE_BIN" >/dev/null 2>&1 || return 1
  if command -v timeout >/dev/null 2>&1; then
    timeout "${TIMEOUT}s" "$CLAUDE_BIN" -p "$PROMPT @$img" --model "$MODEL" --output-format text </dev/null 2>/dev/null
  else
    "$CLAUDE_BIN" -p "$PROMPT @$img" --model "$MODEL" --output-format text </dev/null 2>/dev/null
  fi
}

n=0
for u in "${IMG_URLS[@]}"; do
  n=$((n+1)); idx="$(printf '%02d' "$n")"
  tmp="$(mktemp)"
  code="$(curl -sSL -m 60 --proto '=http,https' --proto-redir '=http,https' -o "$tmp" -w '%{http_code}' "$u" 2>/dev/null || echo 000)"
  if [ "$code" != "200" ] || [ ! -s "$tmp" ]; then
    echo "  filing-$idx SKIP (http $code / empty) $u" >&2; rm -f "$tmp"; continue
  fi
  sz="$(wc -c < "$tmp" | tr -d ' ')"
  if [ "$sz" -le 1024 ]; then
    echo "  filing-$idx SKIP (too small: ${sz}B) $u" >&2; rm -f "$tmp"; continue
  fi
  case "$(file -b "$tmp" 2>/dev/null)" in
    *PNG*)  ext=png ;;
    *JPEG*) ext=jpg ;;
    *WebP*) ext=webp ;;
    *TIFF*) ext=tif ;;
    *) echo "  filing-$idx SKIP (not an image) $u" >&2; rm -f "$tmp"; continue ;;
  esac
  OUT="$DIR/filing-$idx.$ext"
  mv "$tmp" "$OUT" || die "cannot write $OUT"
  sha="$(sha256sum "$OUT" | cut -d' ' -f1)"

  # Stage 2: transcribe (non-fatal).
  md="$DIR/filing-$idx.md"; trans_ok=0
  txt="$(run_transcriber "$OUT")"
  if [ -n "$txt" ]; then
    trans_ok=1
    { printf '<!-- AI-ASSISTED TRANSCRIPTION — NOT verbatim OCR. Verify against the image before citing.\n'
      printf '     Source image: filing-%s.%s (sha256 %s)\n' "$idx" "$ext" "$sha"
      printf '     Transcriber: %s, retrieved %s -->\n\n' "$CLAUDE_VER" "$RETRIEVED"
      printf '> **⚠️ AI-ASSISTED TRANSCRIPTION — not verbatim OCR. Verify against the source image.**\n\n'
      printf '%s\n' "$txt"
    } > "$md"
  else
    rm -f "$md"
  fi

  # Stage 3: emit the register block (stdout) + a one-line summary (stderr).
  echo "- id: src-TODO-$n"
  echo "  origin: $URL#filing-$idx"
  echo "  url: $URL"
  echo "  archive_url: $OUT"
  echo "  sha256: $sha"
  if [ "$trans_ok" -eq 1 ]; then echo "  companion_transcription: $md"; else echo "  companion_transcription: (transcription failed)"; fi
  echo "  retrieved: $RETRIEVED"
  echo "  note: \"Photographed court filing embedded in the source post; AI-assisted transcription (verify against image).\""
  echo "  $OUT $sha transcription=$([ "$trans_ok" -eq 1 ] && echo ok || echo failed)" >&2
  OUT=""
done
exit 0
