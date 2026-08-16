#!/usr/bin/env bash
# gleif.sh — GLEIF LEI API (free, no key). capture-evidence.sh lineage.
# Usage: gleif.sh [--jq FILTER] <search|record|parent|children> <arg>
#   search "<legalName>" | record <LEI> | parent <LEI> | children <LEI>
# Auth: none. parent/children return HTTP 404 when no relationship is on record —
# that is a clean "none on record" success (archived as negative evidence), not a failure.
TOOL="gleif"
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/_registry-lib.sh"
BASE="https://api.gleif.org/api/v1"

JQFILTER=""; ARGS=()
while [ $# -gt 0 ]; do case "$1" in
  --jq) JQFILTER="${2:-}"; shift 2 ;;
  *) ARGS+=("$1"); shift ;;
esac; done
[ "${#ARGS[@]}" -eq 2 ] || die "usage: gleif.sh [--jq FILTER] <search|record|parent|children> <arg>"
CMD="${ARGS[0]}"; ARG="${ARGS[1]}"

# gleif_rel_get URL — like reg_get but returns the body (stdout) AND exit 0 for the GLEIF
# 404 "Related resource not found" envelope, so the caller can treat it as an empty result.
# die()s on every other non-2xx. The caller distinguishes empty by inspecting the body.
gleif_rel_get(){
  local url="$1" tmp code
  tmp="$(mktemp)"
  code="$(curl -sS -m 45 "$url" -o "$tmp" -w '%{http_code}' 2>/dev/null || echo 000)"
  case "$code" in
    2*)  cat "$tmp"; rm -f "$tmp"; return 0 ;;
    404) if jq -e '.errors[0].status=="404"' "$tmp" >/dev/null 2>&1; then
           cat "$tmp"; rm -f "$tmp"; return 0   # empty-relationship envelope — caller handles
         else rm -f "$tmp"; die "not found (http 404): $url"; fi ;;
    401|403) rm -f "$tmp"; die "auth rejected (http $code) for $url" ;;
    429) rm -f "$tmp"; die "rate limited (http 429): $url" ;;
    *)   rm -f "$tmp"; die "request failed (http ${code:-000}): $url" ;;
  esac
}

case "$CMD" in
  search)
    URL="$BASE/lei-records?filter%5Bentity.legalName%5D=$(jq -rn --arg q "$ARG" '$q|@uri')&page%5Bsize%5D=10"
    BODY="$(reg_get "$URL")" || exit 1
    reg_validate_json "$BODY" '.data'
    reg_archive "gleif" "search" "$ARG" "$BODY"
    SUM="$(printf '%s' "$BODY" | jq -r '"\(.meta.pagination.total) results"' 2>/dev/null || echo '-')"
    ;;
  record)
    URL="$BASE/lei-records/$ARG"
    BODY="$(reg_get "$URL")" || exit 1
    reg_validate_json "$BODY" '.data.id'
    reg_archive "gleif" "record" "$ARG" "$BODY"
    SUM="$(printf '%s' "$BODY" | jq -r '"\(.data.attributes.entity.legalName.name) [\(.data.attributes.entity.status)] \(.data.id)"' 2>/dev/null || echo '-')"
    ;;
  parent)
    URL="$BASE/lei-records/$ARG/direct-parent"
    BODY="$(gleif_rel_get "$URL")" || exit 1
    if printf '%s' "$BODY" | jq -e '.errors[0].status=="404"' >/dev/null 2>&1; then
      reg_archive "gleif" "parent" "$ARG" "$BODY"; SUM="no direct parent on record"
    else
      reg_validate_json "$BODY" '.data'
      reg_archive "gleif" "parent" "$ARG" "$BODY"
      SUM="$(printf '%s' "$BODY" | jq -r '"\(.data.attributes.entity.legalName.name)"' 2>/dev/null || echo '-')"
    fi
    ;;
  children)
    URL="$BASE/lei-records/$ARG/direct-children?page%5Bsize%5D=50"
    BODY="$(gleif_rel_get "$URL")" || exit 1
    if printf '%s' "$BODY" | jq -e '.errors[0].status=="404"' >/dev/null 2>&1; then
      reg_archive "gleif" "children" "$ARG" "$BODY"; SUM="no direct children on record"
    else
      reg_validate_json "$BODY" '.data'
      reg_archive "gleif" "children" "$ARG" "$BODY"
      SUM="$(printf '%s' "$BODY" | jq -r '"\((.meta.pagination.total // (.data|length))) children"' 2>/dev/null || echo '-')"
    fi
    ;;
  *) die "unknown command: $CMD (search|record|parent|children)" ;;
esac

echo "$REG_ARCHIVE_PATH $REG_ARCHIVE_SHA $SUM"
[ -n "$JQFILTER" ] && printf '%s' "$BODY" | jq "$JQFILTER"
exit 0
