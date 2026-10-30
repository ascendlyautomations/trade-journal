#!/usr/bin/env bash
# Apply bootstrap/002 after placeholders are resolved (no active SQL until then).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TRADETRAXS_STAGING_ROOT="$ROOT/supabase/staging"
# shellcheck source=supabase/staging/scripts/lib/project-guard.sh
source "$ROOT/supabase/staging/scripts/lib/project-guard.sh"
tradetraxs_load_staging_local_env
tradetraxs_prepend_pg_client_path

SEED="$ROOT/supabase/staging/bootstrap/002_staging_reference_seed.sql"

tradetraxs_assert_staging_env

if [[ -z "${TRADETRAXS_STAGING_DATABASE_URL:-}" ]]; then
  echo "error: set TRADETRAXS_STAGING_DATABASE_URL" >&2
  exit 1
fi

tradetraxs_assert_staging_live_database "$TRADETRAXS_STAGING_DATABASE_URL"

if [[ "${TRADETRAXS_STAGING_SEED_READY:-}" != "yes" ]]; then
  echo "error: set TRADETRAXS_STAGING_SEED_READY=yes after editing 002 and uncommenting inserts" >&2
  exit 1
fi

tradetraxs_assert_seed_file_safe "$SEED"

echo "Applying staging reference seed..."
psql "$TRADETRAXS_STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$SEED"
