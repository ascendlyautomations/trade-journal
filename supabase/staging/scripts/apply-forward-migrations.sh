#!/usr/bin/env bash
# Apply ONLY migrations listed in forward_migrations.manifest.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TRADETRAXS_STAGING_ROOT="$ROOT/supabase/staging"
# shellcheck source=supabase/staging/scripts/lib/project-guard.sh
source "$ROOT/supabase/staging/scripts/lib/project-guard.sh"
tradetraxs_load_staging_local_env
tradetraxs_prepend_pg_client_path

MANIFEST="$ROOT/supabase/staging/forward_migrations.manifest"

tradetraxs_assert_staging_env

if [[ -z "${TRADETRAXS_STAGING_DATABASE_URL:-}" ]]; then
  echo "error: set TRADETRAXS_STAGING_DATABASE_URL" >&2
  exit 1
fi

tradetraxs_assert_staging_live_database "$TRADETRAXS_STAGING_DATABASE_URL"
tradetraxs_assert_verification_stamp "$TRADETRAXS_STAGING_PROJECT_REF" "no"

if [[ ! -f "$MANIFEST" ]]; then
  echo "error: missing $MANIFEST" >&2
  exit 1
fi

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="$(echo "$line" | xargs)"
  [[ -z "$line" ]] && continue
  if [[ "$line" == skip:* ]]; then
    echo "skip: ${line#skip:}"
    continue
  fi
  path="$ROOT/$line"
  if [[ ! -f "$path" ]]; then
    echo "error: migration not found: $path" >&2
    exit 1
  fi
  echo "apply: $line"
  psql "$TRADETRAXS_STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$path"
done < "$MANIFEST"

# Forward apply invalidates forward stamp until re-verified.
python3 - "$(tradetraxs_verification_stamp_path)" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    doc = json.load(f)
doc["forward_verified"] = False
doc["forward_applied_at_utc"] = __import__("datetime").datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
with open(path, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY

echo "Forward migrations applied. Run: ./supabase/staging/scripts/run-verify.sh forward (or all)"
