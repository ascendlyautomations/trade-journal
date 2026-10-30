#!/usr/bin/env bash
# Run verification SQL against staging with live DB identity checks.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TRADETRAXS_STAGING_ROOT="$ROOT/supabase/staging"
# shellcheck source=supabase/staging/scripts/lib/project-guard.sh
source "$ROOT/supabase/staging/scripts/lib/project-guard.sh"
tradetraxs_load_staging_local_env
tradetraxs_prepend_pg_client_path

MODE="${1:-baseline}"

tradetraxs_assert_staging_env

if [[ -z "${TRADETRAXS_STAGING_DATABASE_URL:-}" ]]; then
  echo "error: set TRADETRAXS_STAGING_DATABASE_URL" >&2
  exit 1
fi

tradetraxs_assert_staging_live_database "$TRADETRAXS_STAGING_DATABASE_URL"

run_sql() {
  local file="$1"
  echo "verify: $(basename "$file")"
  psql "$TRADETRAXS_STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$file"
}

case "$MODE" in
  baseline)
    run_sql "$ROOT/supabase/staging/verify/schema_verification.sql"
    tradetraxs_write_verification_stamp "$TRADETRAXS_STAGING_PROJECT_REF" "baseline"
    ;;
  forward)
    tradetraxs_assert_verification_stamp "$TRADETRAXS_STAGING_PROJECT_REF" "no"
    run_sql "$ROOT/supabase/staging/verify/schema_verification_forward.sql"
    tradetraxs_write_verification_stamp "$TRADETRAXS_STAGING_PROJECT_REF" "forward"
    ;;
  all)
    run_sql "$ROOT/supabase/staging/verify/schema_verification.sql"
    run_sql "$ROOT/supabase/staging/verify/schema_verification_forward.sql"
    tradetraxs_write_verification_stamp "$TRADETRAXS_STAGING_PROJECT_REF" "all"
    ;;
  *)
    echo "usage: $0 [baseline|forward|all]" >&2
    exit 1
    ;;
esac

echo "Verification stamp written: $(tradetraxs_verification_stamp_path)"
