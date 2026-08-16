#!/usr/bin/env bash
# companies-house.sh — UK Companies House API (free key). capture-evidence.sh lineage.
# Usage: companies-house.sh [--jq FILTER] <search|osearch|profile|officers|appointments|psc|filings> <arg>
#   search "<query>" | osearch "<officer name>" | profile <no> | officers <no>
#   appointments <officer_id> | psc <no> | filings <no>
# Auth: HTTP Basic, API key as username, empty password. Key env: COMPANIES_HOUSE_API_KEY.
TOOL="companies-house"
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/_registry-lib.sh"
BASE="https://api.company-information.service.gov.uk"

JQFILTER=""; ARGS=()
while [ $# -gt 0 ]; do case "$1" in
  --jq) JQFILTER="${2:-}"; shift 2 ;;
  *) ARGS+=("$1"); shift ;;
esac; done
[ "${#ARGS[@]}" -eq 2 ] || die "usage: companies-house.sh [--jq FILTER] <search|osearch|profile|officers|appointments|psc|filings> <arg>"
CMD="${ARGS[0]}"; ARG="${ARGS[1]}"
reg_require_key COMPANIES_HOUSE_API_KEY "register free at developer.company-information.service.gov.uk"

case "$CMD" in
  search)   URL="$BASE/search/companies?q=$(jq -rn --arg q "$ARG" '$q|@uri')"; ASSERT='.items'; SUMMARY='"\(.total_results) results"' ;;
  osearch)  URL="$BASE/search/officers?q=$(jq -rn --arg q "$ARG" '$q|@uri')"; ASSERT='.items'; SUMMARY='"\(.total_results) results"' ;;
  profile)  URL="$BASE/company/$ARG"; ASSERT='.company_number'; SUMMARY='"\(.company_name) [\(.company_status)] \(.company_number)"' ;;
  officers) URL="$BASE/company/$ARG/officers"; ASSERT='.items'; SUMMARY='"\(.total_results) officers"' ;;
  appointments) URL="$BASE/officers/$ARG/appointments"; ASSERT='.items'; SUMMARY='"\(.name): \((.total_results // (.items|length))) appointments"' ;;
  psc)      URL="$BASE/company/$ARG/persons-with-significant-control"; ASSERT='.items'; SUMMARY='"\((.total_results // (.items|length))) PSC"' ;;
  filings)  URL="$BASE/company/$ARG/filing-history"; ASSERT='.items'; SUMMARY='"\((.total_count // (.items|length))) filings"' ;;
  *) die "unknown command: $CMD (search|osearch|profile|officers|appointments|psc|filings)" ;;
esac

BODY="$(reg_get "$URL" -u "$COMPANIES_HOUSE_API_KEY:")" || exit 1   # reg_get die()s in a subshell; propagate
reg_validate_json "$BODY" "$ASSERT"
reg_archive "companies-house" "$CMD" "$ARG" "$BODY"
SUM="$(printf '%s' "$BODY" | jq -r "$SUMMARY" 2>/dev/null || echo '-')"
echo "$REG_ARCHIVE_PATH $REG_ARCHIVE_SHA $SUM"
[ -n "$JQFILTER" ] && printf '%s' "$BODY" | jq "$JQFILTER"
exit 0
