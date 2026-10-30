#!/usr/bin/env bash
# Restore staging baseline: application DDL, platform hooks, storage buckets.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TRADETRAXS_STAGING_ROOT="$ROOT/supabase/staging"
# shellcheck source=supabase/staging/scripts/lib/project-guard.sh
source "$ROOT/supabase/staging/scripts/lib/project-guard.sh"
tradetraxs_load_staging_local_env
tradetraxs_prepend_pg_client_path

APP_SQL="$ROOT/supabase/staging/artifacts/schema_application.sql"
PLATFORM_SQL="$ROOT/supabase/staging/artifacts/schema_platform_custom.sql"
STAMP="$(tradetraxs_verification_stamp_path)"

tradetraxs_assert_staging_env

if [[ -z "${TRADETRAXS_STAGING_DATABASE_URL:-}" ]]; then
  echo "error: set TRADETRAXS_STAGING_DATABASE_URL" >&2
  exit 1
fi

tradetraxs_assert_staging_live_database "$TRADETRAXS_STAGING_DATABASE_URL"

if [[ ! -f "$APP_SQL" || ! -f "$PLATFORM_SQL" ]]; then
  echo "error: missing export artifacts — run export-production-schema.sh first" >&2
  echo "  expected: $APP_SQL" >&2
  echo "  expected: $PLATFORM_SQL" >&2
  exit 1
fi

tradetraxs_validate_staging_export_artifacts "$APP_SQL" "$PLATFORM_SQL"

# Reset verification stamp on fresh restore (fail closed for forward apply / repair).
rm -f "$STAMP"

PSQL=(psql "$TRADETRAXS_STAGING_DATABASE_URL" -v ON_ERROR_STOP=1)

echo "Restoring application schema (public, demo) to staging ref $TRADETRAXS_STAGING_PROJECT_REF ..."
"${PSQL[@]}" -f "$APP_SQL"

echo "Restoring platform custom hooks (auth signup trigger, storage policies) ..."
"${PSQL[@]}" -f "$PLATFORM_SQL"

echo "Applying storage bucket bootstrap (001) ..."
"${PSQL[@]}" -f "$ROOT/supabase/staging/bootstrap/001_storage_buckets.sql"

echo "Restore complete. Run ./supabase/staging/scripts/run-verify.sh baseline"
echo "Reference seed (002) is NOT auto-applied — use seed-staging-reference.sh when ready."
