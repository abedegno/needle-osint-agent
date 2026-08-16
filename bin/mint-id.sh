#!/usr/bin/env bash
# mint-id.sh — mint a canonical ULID id. The ONLY sanctioned way to create a src/lead id.
# Usage: mint-id.sh <src|lead|--raw>                       (current time)
#        mint-id.sh --time <epoch_ms> <src|lead|--raw>     (fixed time; migration)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ULIDPY="$HERE/lib/ulid.py"
die(){ echo "mint-id: ERROR: $*" >&2; echo "usage: mint-id.sh [--time <epoch_ms>] <src|lead|--raw>" >&2; exit 1; }
TIME_ARG=""
if [ "${1:-}" = "--time" ]; then TIME_ARG="${2:-}"; shift 2 || die "--time needs a value"; fi
TYPE="${1:-}"; case "$TYPE" in src|lead|--raw) ;; *) die "type must be src|lead|--raw (got '${TYPE:-}')";; esac
if [ -n "$TIME_ARG" ]; then
  case "$TIME_ARG" in ''|*[!0-9]*) die "--time must be a non-negative integer";; esac
  ULID="$(python3 "$ULIDPY" --new "$TIME_ARG" 2>/dev/null)" || die "ms out of range"
else
  ULID="$(python3 "$ULIDPY" --new)" || die "ulid generation failed"
fi
[ -n "$ULID" ] || die "empty ulid"
case "$TYPE" in --raw) printf '%s\n' "$ULID" ;; *) printf '%s-%s\n' "$TYPE" "$ULID" ;; esac
