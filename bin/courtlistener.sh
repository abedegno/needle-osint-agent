#!/usr/bin/env bash
# courtlistener.sh — CourtListener REST v4 (US courts / RECAP / PACER). capture-evidence.sh lineage.
# Usage: courtlistener.sh [--jq FILTER] <search|docket|recap> <arg>
#   search "<query>" | docket <id> | recap <docket_id>
# Auth: header Authorization: Token <token>. Key env: COURTLISTENER_TOKEN.
TOOL="courtlistener"
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/_registry-lib.sh"
BASE="https://www.courtlistener.com/api/rest/v4"

JQFILTER=""; ARGS=()
while [ $# -gt 0 ]; do case "$1" in
  --jq) JQFILTER="${2:-}"; shift 2 ;;
  *) ARGS+=("$1"); shift ;;
esac; done
[ "${#ARGS[@]}" -eq 2 ] || die "usage: courtlistener.sh [--jq FILTER] <search|docket|recap> <arg>"
CMD="${ARGS[0]}"; ARG="${ARGS[1]}"
reg_require_key COURTLISTENER_TOKEN "register free at courtlistener.com → API token"

case "$CMD" in
  search) URL="$BASE/search/?q=$(jq -rn --arg q "$ARG" '$q|@uri')"; ASSERT='.results'; SUMMARY='"\(.count) results"' ;;
  docket) URL="$BASE/dockets/$ARG/"; ASSERT='.id'; SUMMARY='"\(.case_name // "docket \(.id)")"' ;;
  recap)  URL="$BASE/recap-documents/?docket_entry__docket=$ARG"; ASSERT='.results'; SUMMARY='"\(.count) documents"' ;;
  *) die "unknown command: $CMD (search|docket|recap)" ;;
esac

BODY="$(reg_get "$URL" -H "Authorization: Token $COURTLISTENER_TOKEN")" || exit 1   # reg_get die()s in a subshell; propagate
reg_validate_json "$BODY" "$ASSERT"
reg_archive "courtlistener" "$CMD" "$ARG" "$BODY"
SUM="$(printf '%s' "$BODY" | jq -r "$SUMMARY" 2>/dev/null || echo '-')"
echo "$REG_ARCHIVE_PATH $REG_ARCHIVE_SHA $SUM"
[ -n "$JQFILTER" ] && printf '%s' "$BODY" | jq "$JQFILTER"
exit 0
