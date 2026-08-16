#!/usr/bin/env bash
# Capability-track artifact checks for the osint_investigator bundle (VT-1..VT-3).
# Run AFTER a validation session, against that session's workspace root:
#   omnigent/tests/verify-artifacts.sh /workspaces/<your-workspace>
# Exits non-zero if any STRUCTURAL check fails. The real-name / no-pseudonym
# judgement (VT-3) is manual — flagged here, not asserted.
set -uo pipefail
WS="${1:-.}"
fail=0
pass(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
bad(){  printf '  \033[31m❌\033[0m %s\n' "$1"; fail=1; }
note(){ printf '  \033[33m⚠️\033[0m  %s\n' "$1"; }

echo "Workspace: $WS"
echo

echo "VT-1 screenshot capture — evidence/snapshots/*.png"
pngs=$(find "$WS/evidence/snapshots" -maxdepth 1 -name '*.png' 2>/dev/null)
if [ -z "$pngs" ]; then
  bad "no .png in evidence/snapshots/"
else
  ok=0
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    sz=$(wc -c < "$p" | tr -d ' ')
    if file "$p" | grep -qi 'PNG image data' && [ "$sz" -gt 1000 ]; then
      pass "$(basename "$p") — ${sz} bytes, valid PNG"; ok=1
    else
      bad "$(basename "$p") — not a valid PNG or too small (${sz} bytes)"
    fi
  done <<< "$pngs"
  [ "$ok" -eq 1 ] || bad "no valid PNG found"
fi
echo

echo "VT-2 PDF→text — evidence/snapshots/*.pdf + .txt, register.yaml pointer"
pdfs=$(find "$WS/evidence/snapshots" -maxdepth 1 -name '*.pdf' 2>/dev/null)
if [ -z "$pdfs" ]; then
  bad "no .pdf in evidence/snapshots/"
else
  while IFS= read -r pdf; do
    [ -z "$pdf" ] && continue
    txt="${pdf%.pdf}.txt"
    if [ -s "$txt" ]; then pass "$(basename "$txt") — present and non-empty"
    else bad "$(basename "$pdf") — missing/empty .txt snapshot"; fi
  done <<< "$pdfs"
fi
reg="$WS/dossier/sources/register.yaml"
if [ -f "$reg" ]; then
  grep -qiE 'sha-?256' "$reg" && pass "register.yaml has a sha256" \
    || bad "register.yaml has no sha256 entry"
else
  bad "no dossier/sources/register.yaml"
fi
echo

echo "VT-3 people first-class — dossier/people + dossier/findings"
pc=$(find "$WS/dossier/people"   -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
fc=$(find "$WS/dossier/findings" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
[ "${pc:-0}" -gt 0 ] && pass "dossier/people has $pc file(s)"   || bad "dossier/people empty"
[ "${fc:-0}" -gt 0 ] && pass "dossier/findings has $fc file(s)" || bad "dossier/findings empty"
note "VT-3 real-name / no-pseudonym is a MANUAL review — open the people/ files and confirm real names."
echo

echo "VT-4 register integrity — every register.yaml evidence path exists on disk"
if "$(dirname "$0")/verify-register.sh" "$WS" ; then
  pass "register.yaml has no phantom evidence references"
else
  bad "register.yaml references evidence files that are missing on disk"
fi
echo

if [ "$fail" -eq 0 ]; then echo "STRUCTURAL CHECKS PASSED"; else echo "STRUCTURAL CHECKS FAILED"; fi
exit "$fail"
