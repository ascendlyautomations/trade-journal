#!/usr/bin/env bash
# Read-only schema-only export from production. No row data, no secrets files.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TRADETRAXS_STAGING_ROOT="$ROOT/supabase/staging"
# shellcheck source=supabase/staging/scripts/lib/project-guard.sh
source "$ROOT/supabase/staging/scripts/lib/project-guard.sh"
tradetraxs_prepend_pg_client_path

ARTIFACT_DIR="$ROOT/supabase/staging/artifacts"
OUT_APP="$ARTIFACT_DIR/schema_application.sql"
OUT_PLATFORM="$ARTIFACT_DIR/schema_platform_custom.sql"
OUT_MANAGED_RAW="$ARTIFACT_DIR/.managed_schema_raw.sql"
OUT_META="$ARTIFACT_DIR/BASELINE_SNAPSHOT.json"
FILTER_PY="$ROOT/supabase/staging/scripts/lib/split-managed-schema-dump.py"

if [[ -z "${TRADETRAXS_PRODUCTION_DATABASE_URL:-}" ]]; then
  echo "error: set TRADETRAXS_PRODUCTION_DATABASE_URL (read-only role)" >&2
  exit 1
fi

if [[ "${TRADETRAXS_ENV:-}" == "staging" || "${LOADTEST_ENV:-}" == "staging" ]]; then
  echo "error: unset TRADETRAXS_ENV/LOADTEST_ENV=staging for production export (avoid mixed context)" >&2
  exit 1
fi

URL_REF="$(tradetraxs_ref_from_url "$TRADETRAXS_PRODUCTION_DATABASE_URL")"
tradetraxs_assert_production_export_ref "$URL_REF"
tradetraxs_assert_production_live_database "$TRADETRAXS_PRODUCTION_DATABASE_URL"
tradetraxs_assert_export_connection_read_only "$TRADETRAXS_PRODUCTION_DATABASE_URL"

if ! command -v pg_dump >/dev/null 2>&1; then
  echo "error: pg_dump not found" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 not found (required to filter managed-schema dump)" >&2
  exit 1
fi

mkdir -p "$ARTIFACT_DIR"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo "Exporting application schemas (public, demo) from production ref $URL_REF → $OUT_APP"

export PGOPTIONS="${PGOPTIONS:-} -c default_transaction_read_only=on"

pg_dump "$TRADETRAXS_PRODUCTION_DATABASE_URL" \
  --schema-only \
  --no-owner \
  --no-privileges \
  --format=plain \
  --file="$OUT_APP" \
  --schema=public \
  --schema=demo \
  --exclude-schema=supabase_migrations \
  --exclude-schema=vault

echo "Exporting managed schemas (auth, storage) for platform-hook extraction → $OUT_MANAGED_RAW"

pg_dump "$TRADETRAXS_PRODUCTION_DATABASE_URL" \
  --schema-only \
  --no-owner \
  --no-privileges \
  --format=plain \
  --file="$OUT_MANAGED_RAW" \
  --schema=auth \
  --schema=storage \
  --exclude-table=storage.objects

python3 "$FILTER_PY" "$OUT_MANAGED_RAW" "$OUT_PLATFORM"
rm -f "$OUT_MANAGED_RAW"

tradetraxs_validate_staging_export_artifacts "$OUT_APP" "$OUT_PLATFORM"

cat > "$OUT_META" <<EOF
{
  "exported_at_utc": "$TS",
  "source_project_ref": "$URL_REF",
  "export_mode": "schema_only_split",
  "artifacts": {
    "application": "supabase/staging/artifacts/schema_application.sql",
    "platform_custom": "supabase/staging/artifacts/schema_platform_custom.sql"
  },
  "production_migration_ledger_max_version": "20261024042226",
  "production_migration_ledger_max_name": "achievement_payout_firm_assignment",
  "notes": "Application dump excludes auth/storage/realtime base DDL. Platform file restores signup trigger + storage policies only.",
  "never_commit": true
}
EOF

echo "Wrote $OUT_APP ($(wc -c < "$OUT_APP" | tr -d ' ') bytes)"
echo "Wrote $OUT_PLATFORM ($(wc -c < "$OUT_PLATFORM" | tr -d ' ') bytes)"
echo "Wrote $OUT_META"
echo "Manual review: confirm no integration secrets in comments before staging restore."
