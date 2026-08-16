#!/usr/bin/env bash
# _registry-lib.sh — shared helpers for the registry/court API tools (companies-house.sh,
# uspto-tsdr.sh, courtlistener.sh). SOURCED, not executed. capture-evidence.sh lineage:
# authed curl -> jq-validate -> archive raw JSON + SHA256 -> fail loud (never silent success).
# A consumer sets TOOL (error prefix) before sourcing.
set -uo pipefail
: "${REG_EVIDENCE_DIR:=evidence/documents}"
OUT=""  # archive path; die() removes it on failure
REG_ARCHIVE_PATH=""; REG_ARCHIVE_SHA=""

die(){ echo "${TOOL:-registry}: ERROR: $*" >&2; [ -n "${OUT:-}" ] && rm -f "$OUT"; exit 1; }

reg_require_key(){  # reg_require_key VARNAME "hint"
  local var="$1" hint="$2"
  [ -n "${!var:-}" ] || die "$var is empty in this shell — set it in the deployment's \`.env\` and add it to OMNIGENT_RUNNER_ENV_PASSTHROUGH ($hint)"
}

reg_get(){  # reg_get URL [curl auth args...] -> body on 2xx (stdout); die otherwise. One 429 retry (honours Retry-After).
  local url="$1"; shift
  local tmp hdr code ra
  tmp="$(mktemp)"; hdr="$(mktemp)"
  code="$(curl -sS -m 45 "$@" "$url" -D "$hdr" -o "$tmp" -w '%{http_code}' 2>/dev/null || echo 000)"
  if [ "$code" = "429" ]; then
    ra="$(awk 'tolower($1)=="retry-after:"{print $2+0; exit}' "$hdr")"
    sleep "${ra:-3}"
    code="$(curl -sS -m 45 "$@" "$url" -o "$tmp" -w '%{http_code}' 2>/dev/null || echo 000)"
  fi
  rm -f "$hdr"
  case "$code" in
    2*)      cat "$tmp"; rm -f "$tmp"; return 0 ;;
    401|403) rm -f "$tmp"; die "auth rejected (http $code) for $url — check key/token" ;;
    404)     rm -f "$tmp"; die "not found (http 404): $url" ;;
    429)     rm -f "$tmp"; die "rate limited (http 429) after one retry: $url" ;;
    *)       rm -f "$tmp"; die "request failed (http ${code:-000}): $url" ;;
  esac
}

reg_validate_json(){  # reg_validate_json BODY 'jq assertion'
  local body="$1" assert="$2"
  printf '%s' "$body" | jq -e "$assert" >/dev/null 2>&1 || die "response failed validation ($assert) — malformed or error envelope"
}

reg_archive(){  # reg_archive SOURCE COMMAND KEY BODY ; sets REG_ARCHIVE_PATH + REG_ARCHIVE_SHA
  local source="$1" command="$2" key="$3" body="$4" date n=1 wantsha
  date="$(date +%F)"
  key="$(printf '%s' "$key" | tr -cs 'A-Za-z0-9._-' '_')"
  mkdir -p "$REG_EVIDENCE_DIR" || die "cannot create $REG_EVIDENCE_DIR"
  OUT="$REG_EVIDENCE_DIR/${source}_${command}_${key}_${date}.json"
  wantsha="$(printf '%s' "$body" | sha256sum | cut -d' ' -f1)"
  while [ -e "$OUT" ] && [ "$(sha256sum "$OUT" | cut -d' ' -f1)" != "$wantsha" ]; do
    OUT="$REG_EVIDENCE_DIR/${source}_${command}_${key}_${date}_$n.json"; n=$((n+1))
  done
  printf '%s' "$body" > "$OUT" || die "cannot write $OUT"
  REG_ARCHIVE_PATH="$OUT"; REG_ARCHIVE_SHA="$(sha256sum "$OUT" | cut -d' ' -f1)"
}
