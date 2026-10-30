#!/usr/bin/env bash
# Restore full production logical backup into allowlisted staging only.
# https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
TRADETRAXS_STAGING_ROOT="$ROOT/supabase/staging"
# shellcheck source=supabase/staging/scripts/lib/project-guard.sh
source "$ROOT/supabase/staging/scripts/lib/project-guard.sh"
tradetraxs_load_staging_local_env
tradetraxs_prepend_pg_client_path

OUT_DIR="$(tradetraxs_full_clone_artifact_dir)"
HARDENING="$ROOT/supabase/staging/scripts/full-clone/post-restore-hardening.sql"
VERIFY="$ROOT/supabase/staging/scripts/full-clone/verify-full-clone.sql"

tradetraxs_assert_full_clone_restore_env
tradetraxs_assert_full_clone_backup_artifacts

if [[ "${TRADETRAXS_SKIP_STAGING_SNAPSHOT:-}" != "yes" ]]; then
  echo "restore: creating staging rollback snapshot first (set TRADETRAXS_SKIP_STAGING_SNAPSHOT=yes to skip)..."
  "$ROOT/supabase/staging/scripts/full-clone/backup-staging-snapshot.sh"
fi

echo "restore: applying roles + schema + data to staging ref $TRADETRAXS_STAGING_PROJECT_REF ..."

psql \
  "$TRADETRAXS_STAGING_DATABASE_URL" \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file "$OUT_DIR/roles.sql" \
  --file "$OUT_DIR/schema.sql" \
  --command 'SET session_replication_role = replica' \
  --file "$OUT_DIR/data.sql"

if [[ -s "$OUT_DIR/history_schema.sql" && -s "$OUT_DIR/history_data.sql" ]]; then
  echo "restore: migration history (supabase_migrations)..."
  psql \
    "$TRADETRAXS_STAGING_DATABASE_URL" \
    --single-transaction \
    --variable ON_ERROR_STOP=1 \
    --file "$OUT_DIR/history_schema.sql" \
    --file "$OUT_DIR/history_data.sql"
fi

echo "restore: post-restore hardening (side-effect gates)..."
psql "$TRADETRAXS_STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$HARDENING"

echo "restore: verification..."
psql "$TRADETRAXS_STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$VERIFY"

echo "Restore complete. Run copy-storage-objects.sh, deploy Edge Functions, configure Auth/OAuth on staging."
echo "Apply docs/SIDE_EFFECT_GATES.md before any app traffic."
