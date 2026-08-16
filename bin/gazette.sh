#!/usr/bin/env bash
# gazette.sh — The Gazette (UK official public record) data.json API (free, no key).
# Usage: gazette.sh [--jq FILTER] <search> <text>
#   search "<text>"   full-text notice search (insolvency, disqualification, strike-off, …)
# Auth: none. Archives the raw Atom-feed-as-JSON (total at .["f:total"], notices under .entry[]).
# Default stdout AFTER the `path sha summary` line is a TIDY normalized view so callers don't
# reverse-engineer the f:/link schema:  {total, notices:[{code,title,name,date,link}]}.
# Pass --jq FILTER to override with your own query over the raw body (e.g. .entry[].content).
TOOL="gazette"
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/_registry-lib.sh"
BASE="https://www.thegazette.co.uk/all-notices/notice/data.json"

# Tidy view over the raw Atom-as-JSON. Robust to entry/link being array|object|absent.
NORM='{total:(.["f:total"]|tonumber), notices:[ (.entry // [] | if type=="array" then . else [.] end)[] | {code:.["f:notice-code"], title, name:(.["f:name"] // .["f:familyName"] // null), date:(.published // .updated), link:([ (.link // [] | if type=="array" then . else [.] end)[] | .["@href"] ] | map(select(. != null)) | ((map(select(test("/notice/")))[0]) // .[0]) | (if (. != null) and (startswith("http")|not) then "https://www.thegazette.co.uk"+. else . end))} ]}'

JQFILTER=""; ARGS=()
while [ $# -gt 0 ]; do case "$1" in
  --jq) JQFILTER="${2:-}"; shift 2 ;;
  *) ARGS+=("$1"); shift ;;
esac; done
[ "${#ARGS[@]}" -eq 2 ] || die "usage: gazette.sh [--jq FILTER] <search> <text>"
CMD="${ARGS[0]}"; ARG="${ARGS[1]}"

case "$CMD" in
  search) URL="$BASE?text=$(jq -rn --arg q "$ARG" '$q|@uri')&results-page-size=20" ;;
  *) die "unknown command: $CMD (search)" ;;
esac

BODY="$(reg_get "$URL")" || exit 1
reg_validate_json "$BODY" '(.["f:total"]|tonumber|type=="number")'
reg_archive "gazette" "$CMD" "$ARG" "$BODY"
SUM="$(printf '%s' "$BODY" | jq -r '"\(.["f:total"]) notices"' 2>/dev/null || echo '-')"
echo "$REG_ARCHIVE_PATH $REG_ARCHIVE_SHA $SUM"
if [ -n "$JQFILTER" ]; then printf '%s' "$BODY" | jq "$JQFILTER"
else printf '%s' "$BODY" | jq "$NORM"; fi
exit 0
