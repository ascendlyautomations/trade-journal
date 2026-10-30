#!/usr/bin/env bash
# Verify production URL identity and read-only session (no writes).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
TRADETRAXS_STAGING_ROOT="$ROOT/supabase/staging"
# shellcheck source=supabase/staging/scripts/lib/project-guard.sh
source "$ROOT/supabase/staging/scripts/lib/project-guard.sh"
tradetraxs_prepend_pg_client_path
tradetraxs_load_production_backup_env

unset TRADETRAXS_ENV LOADTEST_ENV
tradetraxs_assert_production_backup_env
tradetraxs_assert_production_backup_read_only_ops

export PGOPTIONS="${PGOPTIONS:-} -c default_transaction_read_only=on"

DB_URL="$TRADETRAXS_PRODUCTION_DATABASE_URL"

tradetraxs_assert_production_backup_ssl_in_use "$DB_URL"

ro="$(psql "$DB_URL" -X -Atqc "SHOW transaction_read_only;")"
if [[ "$ro" != "on" ]]; then
  echo "error: expected transaction_read_only=on (got $ro)" >&2
  exit 1
fi

psql "$DB_URL" -X -Atqc "SELECT 1;" >/dev/null

if psql "$DB_URL" -X -Atqc "CREATE TEMP TABLE tradetraxs_ro_probe(id int);" 2>/dev/null; then
  echo "error: read-only session allowed CREATE TEMP TABLE" >&2
  exit 1
fi

echo "verify: production ref ${TRADETRAXS_PRODUCTION_PROJECT_REF} — session pooler, SSL, read-only OK"
