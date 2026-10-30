#!/usr/bin/env bash
# Copy Storage objects prod → staging (metadata comes from DB restore; bytes are separate).
# Does not run until credentials are set. Uses service role in env — never commit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
TRADETRAXS_STAGING_ROOT="$ROOT/supabase/staging"
# shellcheck source=supabase/staging/scripts/lib/project-guard.sh
source "$ROOT/supabase/staging/scripts/lib/project-guard.sh"
tradetraxs_load_staging_local_env

tradetraxs_assert_staging_env

PROD_REF="$TRADETRAXS_PRODUCTION_PROJECT_REF"
STAGING_REF="$(tradetraxs_resolve_staging_project_ref)"
tradetraxs_assert_staging_ref "$STAGING_REF"

for var in TRADETRAXS_PRODUCTION_SUPABASE_URL TRADETRAXS_PRODUCTION_SERVICE_ROLE_KEY \
  TRADETRAXS_STAGING_SUPABASE_URL TRADETRAXS_STAGING_SERVICE_ROLE_KEY; do
  if [[ -z "${!var:-}" ]]; then
    echo "error: set $var in shell (see full-clone/.env.example)" >&2
    exit 1
  fi
done

tradetraxs_assert_no_production_host "$TRADETRAXS_STAGING_SUPABASE_URL"
if [[ "$TRADETRAXS_STAGING_SUPABASE_URL" != *"$STAGING_REF"* ]]; then
  echo "error: staging Supabase URL must contain $STAGING_REF" >&2
  exit 1
fi
if [[ "$TRADETRAXS_PRODUCTION_SUPABASE_URL" != *"$PROD_REF"* ]]; then
  echo "error: production Supabase URL must contain $PROD_REF" >&2
  exit 1
fi

tradetraxs_assert_not_service_role_key "${LOADTEST_SUPABASE_ANON_KEY:-}"

if [[ "${TRADETRAXS_STORAGE_COPY_CONFIRM:-}" != "yes" ]]; then
  echo "error: set TRADETRAXS_STORAGE_COPY_CONFIRM=yes to copy objects (reads prod, writes staging)" >&2
  exit 1
fi

echo "Storage copy is operator-run. Install a bulk tool (e.g. rclone with S3-compatible Supabase Storage,"
echo "or a one-off script using Storage list/download/upload APIs)."
echo ""
echo "Buckets to mirror (from verify SQL): avatars, screenshots, profile_posts, stories, reels,"
echo "csv-support, message-audio, draft-media, demo-media, bug-reports, email-assets, group-avatars"
echo ""
echo "Preserve object paths so storage.objects rows from DB restore remain valid."
echo "Ref: https://supabase.com/docs/guides/platform/backups (Storage not in DB backups)"

exit 0
