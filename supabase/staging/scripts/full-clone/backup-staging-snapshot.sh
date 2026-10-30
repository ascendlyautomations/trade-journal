#!/usr/bin/env bash
# Pre-restore snapshot of staging for rollback (writes only on staging).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
TRADETRAXS_STAGING_ROOT="$ROOT/supabase/staging"
# shellcheck source=supabase/staging/scripts/lib/project-guard.sh
source "$ROOT/supabase/staging/scripts/lib/project-guard.sh"
tradetraxs_load_staging_local_env
tradetraxs_prepend_pg_client_path

tradetraxs_assert_staging_env
if [[ -z "${TRADETRAXS_STAGING_DATABASE_URL:-}" ]]; then
  echo "error: set TRADETRAXS_STAGING_DATABASE_URL" >&2
  exit 1
fi
tradetraxs_assert_staging_live_database "$TRADETRAXS_STAGING_DATABASE_URL"

ROLLBACK_DIR="$(tradetraxs_full_clone_artifact_dir)/rollback"
TS="$(date -u +"%Y%m%dT%H%M%SZ")"
OUT="$ROLLBACK_DIR/staging_pre_clone_$TS.dump"

mkdir -p "$ROLLBACK_DIR"
echo "snapshot: staging ref $TRADETRAXS_STAGING_PROJECT_REF → $OUT"

export PGOPTIONS="${PGOPTIONS:-} -c default_transaction_read_only=on"
pg_dump "$TRADETRAXS_STAGING_DATABASE_URL" --format=custom --file="$OUT" --no-owner --no-privileges

echo "Rollback: pg_restore --clean --if-exists --no-owner --dbname \"\$TRADETRAXS_STAGING_DATABASE_URL\" \"$OUT\""
echo "(Only after TRADETRAXS_FULL_CLONE_CONFIRM=yes and staging identity re-verified.)"
