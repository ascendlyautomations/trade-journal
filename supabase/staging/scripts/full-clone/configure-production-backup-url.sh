#!/usr/bin/env bash
# Write gitignored TRADETRAXS_PRODUCTION_DATABASE_URL (session pooler + URL-encoded password).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
TRADETRAXS_STAGING_ROOT="$ROOT/supabase/staging"
# shellcheck source=supabase/staging/scripts/lib/project-guard.sh
source "$ROOT/supabase/staging/scripts/lib/project-guard.sh"

ENV_FILE="$(tradetraxs_production_backup_env_file)"
POOLER_HOST="${TRADETRAXS_PRODUCTION_POOLER_HOST:-aws-1-us-east-2.pooler.supabase.com}"
USER="postgres.${TRADETRAXS_PRODUCTION_PROJECT_REF}"

read_password() {
  if [[ -n "${TRADETRAXS_PRODUCTION_DB_PASSWORD_FILE:-}" ]]; then
    if [[ ! -f "$TRADETRAXS_PRODUCTION_DB_PASSWORD_FILE" ]]; then
      echo "error: TRADETRAXS_PRODUCTION_DB_PASSWORD_FILE not found" >&2
      exit 1
    fi
    tr -d '\n' < "$TRADETRAXS_PRODUCTION_DB_PASSWORD_FILE"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    echo "error: run interactively or set TRADETRAXS_PRODUCTION_DB_PASSWORD_FILE (chmod 600)" >&2
    exit 1
  fi
  local pw
  read -rs -p "Production database password (input hidden): " pw < /dev/tty
  echo >&2
  printf '%s' "$pw"
}

encode_component() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""))'
}

main() {
  unset TRADETRAXS_ENV LOADTEST_ENV
  local raw_pw encoded_pw url tmp
  raw_pw="$(read_password)"
  if [[ -z "$raw_pw" ]]; then
    echo "error: empty password" >&2
    exit 1
  fi
  encoded_pw="$(printf '%s' "$raw_pw" | encode_component)"
  unset raw_pw
  url="postgresql://${USER}:${encoded_pw}@${POOLER_HOST}:5432/postgres?sslmode=require"
  unset encoded_pw

  mkdir -p "$(dirname "$ENV_FILE")"
  tmp="$(mktemp "$(dirname "$ENV_FILE")/.env.production.local.XXXXXX")"
  chmod 600 "$tmp"
  cat > "$tmp" <<EOF
# Production backup only — gitignored. Do not set TRADETRAXS_ENV here.
TRADETRAXS_PRODUCTION_BACKUP_MODE=session_pooler
TRADETRAXS_PRODUCTION_DATABASE_URL=${url}
EOF
  unset url
  mv "$tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "Wrote $(basename "$ENV_FILE") (mode 600). URL not printed."

  "$ROOT/supabase/staging/scripts/full-clone/verify-production-backup-connection.sh"
}

main "$@"
