#!/usr/bin/env bash
# Launch one autonomous investigation run. Stateless: pulls latest ${OSINT_BRANCH:-master}, then
# runs the bundle (which branches + opens a PR). Intended for the omnigent runner
# on the NAS and for a future n8n/cron trigger. Supervised runs use the omnigent UI.
# NOTE: engine default is "master" for this deployment; a later task may genericize
# this default to "main" once the deployment sets OSINT_BRANCH explicitly. Deployments
# whose default branch is "main" should set OSINT_BRANCH=main.
set -euo pipefail
cd "$(dirname "$0")/.."          # workspace root (the parent of omnigent/)
# Layout guard: this launcher is <workspace>/omnigent/run.sh, so from the workspace
# the bundle must be visible at omnigent/. A bare checkout of the engine repo at its
# OWN root (files at ./, no ./omnigent/) fails here -- the engine must be vendored at
# <workspace>/omnigent/, not the workspace root. See README "Install & layout".
if [ ! -f omnigent/config.yaml ]; then
  echo "run.sh: no engine bundle at ./omnigent/config.yaml (cwd: $(pwd))." >&2
  echo "  Invoke as <workspace>/omnigent/run.sh with the engine vendored at" >&2
  echo "  <workspace>/omnigent/ (not at the workspace root). See README 'Install & layout'." >&2
  exit 2
fi
# Dry-run resolve: print the effective deployment values and exit BEFORE any git op.
if [ -n "${OSINT_PRINT_RESOLVED:-}" ]; then
  echo "BRANCH=${OSINT_BRANCH:-master}"
  echo "REMOTE=${OSINT_REMOTE:-origin}"
  echo "OMNIGENT_URL=${OMNIGENT_URL:-http://omnigent:8000}"
  exit 0
fi
git checkout "${OSINT_BRANCH:-master}"
git pull --ff-only "${OSINT_REMOTE:-origin}" "${OSINT_BRANCH:-master}"
exec omnigent run omnigent/ --server "${OMNIGENT_SERVER:-http://omnigent:8000}"
