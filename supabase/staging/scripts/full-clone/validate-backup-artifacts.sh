#!/usr/bin/env bash
# Validate full-clone backup artifacts (no secrets printed).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
TRADETRAXS_STAGING_ROOT="$ROOT/supabase/staging"
# shellcheck source=supabase/staging/scripts/lib/project-guard.sh
source "$ROOT/supabase/staging/scripts/lib/project-guard.sh"

DIR="$(tradetraxs_full_clone_artifact_dir)"
tradetraxs_assert_full_clone_backup_artifacts

for f in roles.sql schema.sql data.sql history_schema.sql history_data.sql; do
  if [[ -f "$DIR/$f" ]]; then
    echo "artifact $f: $(wc -c < "$DIR/$f" | tr -d ' ') bytes"
  fi
done

if grep -E '^COPY |^\\\\copy ' "$DIR/data.sql" >/dev/null 2>&1; then
  echo "validate: data.sql contains COPY (expected for data-only dump)"
else
  echo "warning: data.sql has no COPY lines — confirm dump succeeded" >&2
fi

if ! grep -qi 'auth' "$DIR/schema.sql" 2>/dev/null && ! grep -qi 'auth\.users' "$DIR/data.sql" 2>/dev/null; then
  echo "warning: auth schema/users not obvious in artifacts — review manually" >&2
fi

if [[ -f "$DIR/BACKUP_SNAPSHOT.json" ]]; then
  echo "validate: BACKUP_SNAPSHOT.json present"
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$DIR/BACKUP_SNAPSHOT.json"
fi

echo "validate: backup artifacts OK"
