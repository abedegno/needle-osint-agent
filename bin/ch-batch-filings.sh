#!/usr/bin/env bash
# ch-batch-filings.sh — batch-fetch CH imaged filings for a set of companies, filtered by form
# type and date, via companies-house-imaged.sh. Prints paste-ready register.yaml blocks (stdout)
# + a summary table (stderr). Never writes register.yaml.
# Usage: ch-batch-filings.sh --companies "no1,no2" [--forms "AP01,CH01"] [--since YYYY-MM-DD] [--out-dir DIR] [--keep-going]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/_registry-lib.sh"
IMAGED="${CH_IMAGED:-$HERE/companies-house-imaged.sh}"
BASE="https://api.company-information.service.gov.uk"

COMPANIES=""; FORMS=""; SINCE=""; OUTDIR="evidence/documents"; KEEPGOING=0
while [ $# -gt 0 ]; do case "$1" in
  --companies)  COMPANIES="${2:-}"; shift 2 ;;
  --forms)      FORMS="${2:-}"; shift 2 ;;
  --since)      SINCE="${2:-}"; shift 2 ;;
  --out-dir)    OUTDIR="${2:-}"; shift 2 ;;
  --keep-going) KEEPGOING=1; shift ;;
  *) die "unknown arg: $1" ;;
esac; done
[ -n "$COMPANIES" ] || die "usage: ch-batch-filings.sh --companies \"no1,no2\" [--forms ...] [--since YYYY-MM-DD] [--out-dir DIR] [--keep-going]"
reg_require_key COMPANIES_HOUSE_API_KEY "register free at developer.company-information.service.gov.uk"

forms_match(){ [ -z "$FORMS" ] && return 0; local t; t="$(printf '%s' "$1" | tr a-z A-Z)"; case ",$(printf '%s' "$FORMS" | tr a-z A-Z)," in *",$t,"*) return 0 ;; *) return 1 ;; esac; }
date_ok(){ [ -z "$SINCE" ] && return 0; [ "$1" \> "$SINCE" ] || [ "$1" = "$SINCE" ]; }
sanitize(){ printf '%s' "$1" | sed 's/[^A-Za-z0-9]/_/g'; }

n_ok=0; n_fail=0; n_nodoc=0
IFS=',' read -ra CO <<< "$COMPANIES"
for company in "${CO[@]}"; do
  company="$(printf '%s' "$company" | tr -d ' ')"; [ -n "$company" ] || continue
  start=0; total=1
  while [ "$start" -lt "$total" ]; do
    body="$(reg_get "$BASE/company/$company/filing-history?items_per_page=100&start_index=$start" -u "$COMPANIES_HOUSE_API_KEY:")" \
      || { echo "FAILED $company: filing-history fetch" >&2; n_fail=$((n_fail+1)); [ "$KEEPGOING" -eq 1 ] && break || die "filing-history fetch failed for $company"; }
    total="$(printf '%s' "$body" | jq -r '.total_count // (.items|length) // 0')"
    cnt="$(printf '%s' "$body" | jq -r '.items | length')"
    [ "$cnt" -gt 0 ] || break
    for i in $(seq 0 $((cnt-1))); do
      type="$(printf '%s' "$body" | jq -r ".items[$i].type // empty")"
      date="$(printf '%s' "$body" | jq -r ".items[$i].date // empty")"
      meta="$(printf '%s' "$body" | jq -r ".items[$i].links.document_metadata // empty")"
      forms_match "$type" || continue
      date_ok "$date" || continue
      if [ -z "$meta" ]; then echo "no-document $company $type $date" >&2; n_nodoc=$((n_nodoc+1)); continue; fi
      docid="${meta%/content}"; docid="${docid##*/}"
      out="$OUTDIR/ch_${company}_$(sanitize "$type")_${date}_$(printf '%s' "$docid" | cut -c1-12).pdf"
      if block="$("$IMAGED" --company "$company" --form "$type" --filed "$date" "$docid" "$out" 2>/dev/null)"; then
        printf '%s\n' "$block"; echo "ok $company $type $date $out" >&2; n_ok=$((n_ok+1))
      else
        echo "FAILED $company $type $date" >&2; n_fail=$((n_fail+1))
        [ "$KEEPGOING" -eq 1 ] || die "imaged fetch failed for $company $type $date (use --keep-going to continue)"
      fi
    done
    start=$((start+cnt))
  done
done
echo "summary: ok=$n_ok failed=$n_fail no-document=$n_nodoc" >&2
{ [ "$n_fail" -eq 0 ] || [ "$KEEPGOING" -eq 1 ]; } || exit 1
exit 0
