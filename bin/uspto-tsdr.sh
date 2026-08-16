#!/usr/bin/env bash
# uspto-tsdr.sh — USPTO Trademark Status & Document Retrieval (TSDR) API. capture-evidence.sh lineage.
# Usage: uspto-tsdr.sh [--jq FILTER] status <number> [--sn|--rn]
#   status <8-digit serial | 7-digit registration>. Auto-detects by length; override with --sn/--rn.
# Auth: header USPTO-API-KEY. Key env: USPTO_API_KEY.
TOOL="uspto-tsdr"
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/_registry-lib.sh"
BASE="https://tsdrapi.uspto.gov/ts/cd"

JQFILTER=""; FORCE=""; ARGS=()
while [ $# -gt 0 ]; do case "$1" in
  --jq) JQFILTER="${2:-}"; shift 2 ;;
  --sn) FORCE="sn"; shift ;;
  --rn) FORCE="rn"; shift ;;
  *) ARGS+=("$1"); shift ;;
esac; done
[ "${#ARGS[@]}" -eq 2 ] && [ "${ARGS[0]}" = "status" ] || die "usage: uspto-tsdr.sh [--jq FILTER] status <number> [--sn|--rn]"
NUM="${ARGS[1]}"
reg_require_key USPTO_API_KEY "request a TSDR key via the USPTO Open Data Portal"

# Detect serial (8 digits) vs registration (7 digits) unless forced.
KIND="$FORCE"
if [ -z "$KIND" ]; then
  case "${#NUM}" in 8) KIND="sn" ;; 7) KIND="rn" ;; *) die "cannot tell serial vs registration from '$NUM' (8 digits=serial, 7=registration); use --sn/--rn" ;; esac
fi
URL="$BASE/casestatus/${KIND}${NUM}/info.json"

BODY="$(reg_get "$URL" -H "USPTO-API-KEY: $USPTO_API_KEY")" || exit 1   # reg_get die()s in a subshell; propagate
reg_validate_json "$BODY" 'type=="object" and (keys|length>0)'
reg_archive "uspto-tsdr" "status" "${KIND}${NUM}" "$BODY"
SUM="$(printf '%s' "$BODY" | jq -r '.trademarks[0].status as $s | "\($s.markElement // "?") [\($s.tm5StatusDesc // $s.status // "?")] sn\($s.serialNumber // "-")\(if $s.usRegistrationNumber then " rn"+($s.usRegistrationNumber|tostring) else "" end)"' 2>/dev/null || echo '-')"
echo "$REG_ARCHIVE_PATH $REG_ARCHIVE_SHA $SUM"
[ -n "$JQFILTER" ] && printf '%s' "$BODY" | jq "$JQFILTER"
exit 0
