#!/usr/bin/env bash
# Full logical backup from production (read-only dump operations only).
# Follows: https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
TRADETRAXS_STAGING_ROOT="$ROOT/supabase/staging"
# shellcheck source=supabase/staging/scripts/lib/project-guard.sh
source "$ROOT/supabase/staging/scripts/lib/project-guard.sh"
tradetraxs_prepend_pg_client_path
tradetraxs_load_production_backup_env

OUT_DIR="$(tradetraxs_full_clone_artifact_dir)"
META="$OUT_DIR/BACKUP_SNAPSHOT.json"

unset TRADETRAXS_ENV LOADTEST_ENV
tradetraxs_assert_production_backup_env
tradetraxs_assert_production_backup_read_only_ops

"$ROOT/supabase/staging/scripts/full-clone/verify-production-backup-connection.sh"

mkdir -p "$OUT_DIR"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
DB_URL="$TRADETRAXS_PRODUCTION_DATABASE_URL"

export PGOPTIONS="${PGOPTIONS:-} -c default_transaction_read_only=on"

dump_via_cli() {
  if ! command -v supabase >/dev/null 2>&1; then
    return 1
  fi
  echo "backup: using Supabase CLI db dump (read-only) → $OUT_DIR"
  supabase db dump --db-url "$DB_URL" -f "$OUT_DIR/roles.sql" --role-only
  supabase db dump --db-url "$DB_URL" -f "$OUT_DIR/schema.sql"
  supabase db dump --db-url "$DB_URL" -f "$OUT_DIR/data.sql" --use-copy --data-only \
    -x "storage.buckets_vectors" -x "storage.vector_indexes"
  supabase db dump --db-url "$DB_URL" -f "$OUT_DIR/history_schema.sql" --schema supabase_migrations
  supabase db dump --db-url "$DB_URL" -f "$OUT_DIR/history_data.sql" --use-copy --data-only --schema supabase_migrations
  return 0
}

dump_via_pg_dump() {
  echo "backup: using pg_dump (read-only) → $OUT_DIR (install Supabase CLI for recommended dumps)"
  pg_dump "$DB_URL" --format=plain --file="$OUT_DIR/roles.sql" --role-only --no-owner --no-privileges
  pg_dump "$DB_URL" --format=plain --file="$OUT_DIR/schema.sql" --schema-only --no-owner --no-privileges \
    --exclude-schema=supabase_migrations
  pg_dump "$DB_URL" --format=plain --file="$OUT_DIR/data.sql" --data-only --no-owner --no-privileges \
    --exclude-schema=supabase_migrations \
    --exclude-table=storage.buckets_vectors \
    --exclude-table=storage.vector_indexes
  pg_dump "$DB_URL" --format=plain --file="$OUT_DIR/history_schema.sql" --schema-only --no-owner --no-privileges \
    --schema=supabase_migrations
  pg_dump "$DB_URL" --format=plain --file="$OUT_DIR/history_data.sql" --data-only --no-owner --no-privileges \
    --schema=supabase_migrations
}

if dump_via_cli; then
  BACKUP_ENGINE="supabase_cli"
else
  BACKUP_ENGINE="pg_dump"
  dump_via_pg_dump
fi

for f in roles.sql schema.sql data.sql; do
  if [[ ! -s "$OUT_DIR/$f" ]]; then
    echo "error: backup failed to produce $OUT_DIR/$f" >&2
    exit 1
  fi
done

cat > "$META" <<EOF
{
  "backed_up_at_utc": "$TS",
  "source_project_ref": "$TRADETRAXS_PRODUCTION_PROJECT_REF",
  "backup_engine": "$BACKUP_ENGINE",
  "artifacts_dir": "supabase/staging/artifacts/full-clone",
  "files": ["roles.sql", "schema.sql", "data.sql", "history_schema.sql", "history_data.sql"],
  "storage_objects": "not_included",
  "never_commit": true
}
EOF

echo "Wrote production backup under $OUT_DIR (gitignored)."
echo "Next: review sizes, then backup-staging-snapshot.sh before restore."
