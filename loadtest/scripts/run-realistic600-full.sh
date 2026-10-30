#!/usr/bin/env bash
# Run prod-realistic600-full.js with env loaded and loadtest/out/ created (k6 cannot mkdir for summary JSON).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"

mkdir -p loadtest/out

ENV_FILE="${LOADTEST_ENV_FILE:-$REPO/loadtest/.env.production-perf}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: missing env file: $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [[ -z "${LOADTEST_REALISTIC600_FULL_FIXTURE_JSON:-}" && -n "${LOADTEST_REALISTIC600_FULL_FIXTURE_FILE:-}" ]]; then
  if [[ ! -f "$LOADTEST_REALISTIC600_FULL_FIXTURE_FILE" ]]; then
    echo "error: LOADTEST_REALISTIC600_FULL_FIXTURE_FILE not found: $LOADTEST_REALISTIC600_FULL_FIXTURE_FILE" >&2
    exit 1
  fi
  export LOADTEST_REALISTIC600_FULL_FIXTURE_JSON="$(cat "$LOADTEST_REALISTIC600_FULL_FIXTURE_FILE")"
fi

if [[ -z "${LOADTEST_REALISTIC600_FULL_FIXTURE_JSON:-}" ]]; then
  echo "error: set LOADTEST_REALISTIC600_FULL_FIXTURE_JSON or LOADTEST_REALISTIC600_FULL_FIXTURE_FILE" >&2
  exit 1
fi

exec k6 run "$REPO/loadtest/prod-realistic600-full.js" "$@"
