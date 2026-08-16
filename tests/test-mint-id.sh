#!/usr/bin/env bash
# Test for mint-id.sh + ulid.py — canonical ULID minter/validator.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; MINT="$HERE/../bin/mint-id.sh"; ULIDPY="$HERE/../bin/lib/ulid.py"
fail=0
ok(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m❌\033[0m %s\n' "$1"; fail=1; }
skip(){ printf '  \033[33m⏭\033[0m  SKIP: %s\n' "$1"; exit 77; }
command -v python3 >/dev/null 2>&1 || skip "python3 missing"

# (a) src → canonical shape
out="$(bash "$MINT" src)"
printf '%s' "$out" | grep -qE "^src-[0-7][0-9A-HJKMNP-TV-Z]{25}$" && ok "mint src canonical" || no "src: '$out'"
# (b) lead
out="$(bash "$MINT" lead)"
printf '%s' "$out" | grep -qE "^lead-[0-7][0-9A-HJKMNP-TV-Z]{25}$" && ok "mint lead" || no "lead: '$out'"
# (c) --raw round-trips through the canonical decoder
raw="$(bash "$MINT" --raw)"
python3 "$ULIDPY" --check "$raw" && ok "--raw is canonical (round-trips)" || no "raw not canonical: '$raw'"
# (d) uniqueness
[ "$(bash "$MINT" --raw)" != "$(bash "$MINT" --raw)" ] && ok "two mints differ" || no "collision"
# (e) --time fixes the 48-bit time field; two mints share the decoded ms but differ overall
a="$(bash "$MINT" --time 1000000000000 --raw)"; b="$(bash "$MINT" --time 1000000000000 --raw)"
ta="$(python3 "$ULIDPY" --ms "$a")"; tb="$(python3 "$ULIDPY" --ms "$b")"
{ [ "$ta" = 1000000000000 ] && [ "$tb" = 1000000000000 ] && [ "$a" != "$b" ]; } \
  && ok "--time sets exact decoded ms; randomness varies" || no "time: a=$a($ta) b=$b($tb)"
# (f) strict monotonic by decoded time
early="$(bash "$MINT" --time 1000000000000 --raw)"; late="$(bash "$MINT" --time 2000000000000 --raw)"
[ "$early" \< "$late" ] && ok "later ms sorts after earlier" || no "monotonic: $early !< $late"
# (g) forged over-range ULID rejected by the validator (starts with 8 → >128 bits)
python3 "$ULIDPY" --check "8ZZZZZZZZZZZZZZZZZZZZZZZZZZ" && no "forged 8… accepted" || ok "forged 8… rejected"
# (h) invalid alphabet (contains I) rejected
python3 "$ULIDPY" --check "01ARZ3NDEKTSV4RRFFQ69G5FAI" && no "alphabet-invalid accepted" || ok "invalid alphabet rejected"
# (i) --time out of range rejected
bash "$MINT" --time 999999999999999999999 src 2>/dev/null && no "over-range ms accepted" || ok "over-range ms → exit≠0"
# (j) bad type → exit 1
bash "$MINT" bogus 2>/dev/null && no "bad type accepted" || ok "bad type → nonzero"

exit "$fail"
