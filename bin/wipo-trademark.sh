#!/usr/bin/env bash
# wipo-trademark.sh — WIPO Global Brand Database trademark search (owner / brand). Keyless.
# Defeats WIPO's ALTCHA wall + encrypted responses via lib/wipo-search.js (node). reg lineage.
# Usage: wipo-trademark.sh [--jq FILTER] <owner|brand|mark> <query>
#   owner <name>  — marks whose applicant matches <name>
#   brand <text>  — marks whose brandName matches <text>   (mark <number> aliases brand)
set -uo pipefail
TOOL="wipo-trademark"
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/_registry-lib.sh"

JQFILTER=""; ARGS=()
while [ $# -gt 0 ]; do case "$1" in
  --jq) JQFILTER="${2:-}"; shift 2 ;;
  *) ARGS+=("$1"); shift ;;
esac; done
[ "${#ARGS[@]}" -eq 2 ] || die "usage: wipo-trademark.sh [--jq FILTER] <owner|brand|mark> <query>"
MODE="${ARGS[0]}"; QUERY="${ARGS[1]}"
case "$MODE" in
  owner|brand) NMODE="$MODE" ;;
  mark)        NMODE="brand" ;;
  *) die "mode must be owner|brand|mark (got: $MODE)" ;;
esac
command -v node >/dev/null 2>&1 || die "node not found — required for WIPO decryption"

ERR="$(mktemp)"; trap 'rm -f "$ERR"' EXIT
BODY="$(node "$HERE/lib/wipo-search.js" "$NMODE" "$QUERY" 2>"$ERR")" \
  || die "wipo-search failed: $(cat "$ERR")"
printf '%s' "$BODY" | jq -e '.docs' >/dev/null 2>&1 \
  || die "wipo-search returned no docs: $(printf '%s' "$BODY" | head -c 120)"

reg_archive "wipo" "$MODE" "$QUERY" "$BODY"
NF="$(printf '%s' "$BODY" | jq -r '.numFound // 0')"
echo "$REG_ARCHIVE_PATH $REG_ARCHIVE_SHA \"$NF marks for $MODE:$QUERY\""
[ -n "$JQFILTER" ] && printf '%s' "$BODY" | jq "$JQFILTER"
exit 0
