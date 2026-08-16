#!/usr/bin/env bash
# verify-id-integrity.sh — dossier id-integrity gate. Usage: verify-id-integrity.sh [workspace-root]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$HERE/../bin/lib/id_integrity.py" "${1:-.}"
