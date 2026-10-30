#!/usr/bin/env bash
# Mark repo migrations as applied on staging WITHOUT re-running SQL.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TRADETRAXS_STAGING_ROOT="$ROOT/supabase/staging"
# shellcheck source=supabase/staging/scripts/lib/project-guard.sh
source "$ROOT/supabase/staging/scripts/lib/project-guard.sh"
tradetraxs_load_staging_local_env

MANIFEST="$ROOT/supabase/staging/forward_migrations.manifest"

tradetraxs_assert_staging_env

export TRADETRAXS_STAGING_PROJECT_REF="$(tradetraxs_resolve_staging_project_ref)"
tradetraxs_assert_staging_ref "$TRADETRAXS_STAGING_PROJECT_REF"
tradetraxs_assert_cli_not_linked_to_production "$ROOT"

if tradetraxs_forward_manifest_has_apply_lines "$MANIFEST"; then
  tradetraxs_assert_verification_stamp "$TRADETRAXS_STAGING_PROJECT_REF" "yes"
else
  tradetraxs_assert_verification_stamp "$TRADETRAXS_STAGING_PROJECT_REF" "no"
fi

if [[ -n "${TRADETRAXS_STAGING_DATABASE_URL:-}" ]]; then
  tradetraxs_assert_staging_live_database "$TRADETRAXS_STAGING_DATABASE_URL"
fi

if ! command -v supabase >/dev/null 2>&1; then
  echo "error: supabase CLI required" >&2
  exit 1
fi

cd "$ROOT"

while IFS= read -r f; do
  base="$(basename "$f" .sql)"
  ver="${base%%_*}"
  echo "repair applied: $ver ($base)"
  supabase migration repair "$ver" --status applied --project-ref "$TRADETRAXS_STAGING_PROJECT_REF"
done < <(find supabase/migrations -maxdepth 1 -name '*.sql' | sort)

echo "All repo migrations marked applied on staging (CLI --project-ref only; no supabase link)."
