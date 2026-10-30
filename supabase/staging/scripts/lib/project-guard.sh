#!/usr/bin/env bash
# Shared guards: staging bootstrap must never target production.
set -euo pipefail

# Production TradeTraxs Supabase project ref (blocklist + export allowlist only).
readonly TRADETRAXS_PRODUCTION_PROJECT_REF="${TRADETRAXS_PRODUCTION_PROJECT_REF:-fobudrkniacatvilbofw}"

# Sole allowed staging project for restore / forward apply / verify / load tests.
readonly TRADETRAXS_ALLOWED_STAGING_PROJECT_REF="${TRADETRAXS_ALLOWED_STAGING_PROJECT_REF:-hxlcvffvyadlxcsqxxoy}"

readonly TRADETRAXS_PRODUCTION_HOSTS=(
  "tradetraxs.com"
  "www.tradetraxs.com"
  "app.tradetraxs.com"
)

TRADETRAXS_STAGING_ROOT="${TRADETRAXS_STAGING_ROOT:-}"

tradetraxs_prepend_pg_client_path() {
  if command -v pg_dump >/dev/null 2>&1 && command -v psql >/dev/null 2>&1; then
    return 0
  fi
  local dir
  for dir in \
    /opt/homebrew/opt/libpq/bin \
    /opt/homebrew/opt/postgresql@17/bin \
    /usr/local/opt/libpq/bin \
    /usr/local/opt/postgresql@17/bin; do
    if [[ -x "$dir/pg_dump" && -x "$dir/psql" ]]; then
      export PATH="$dir:$PATH"
      return 0
    fi
  done
  echo "error: pg_dump and psql not found; install with: brew install libpq" >&2
  echo "error: then ensure PATH includes Homebrew libpq bin (see brew info libpq)" >&2
  return 1
}

tradetraxs_staging_root() {
  if [[ -n "$TRADETRAXS_STAGING_ROOT" ]]; then
    echo "$TRADETRAXS_STAGING_ROOT"
    return 0
  fi
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  echo "$here"
}

tradetraxs_verification_stamp_path() {
  echo "$(tradetraxs_staging_root)/artifacts/.staging_schema_verified.json"
}

_tradetraxs_extract_project_ref_from_url() {
  local url="${1:-}"
  if [[ -z "$url" ]]; then
    echo ""
    return 0
  fi
  local userpart host
  userpart="$(echo "$url" | sed -E 's#^[a-zA-Z+.-]+://([^:@/]+).*#\1#')"
  if [[ "$userpart" == postgres.* ]]; then
    echo "${userpart#postgres.}"
    return 0
  fi
  if [[ "$url" =~ supabase\.co ]]; then
    host="$(echo "$url" | sed -E 's#^https?://([^./]+)\..*#\1#; s#.*@db\.([^./]+)\..*#\1#')"
    if [[ "$host" != *"/"* && "$host" != *":"* && "$host" != postgres* ]]; then
      echo "$host"
      return 0
    fi
  fi
  echo ""
}

_tradetraxs_ref_from_db_host() {
  local host="${1:-}"
  if [[ "$host" =~ ^db\.([a-z0-9]+)\.supabase\.co$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  echo ""
}

tradetraxs_live_db_host() {
  local url="$1"
  psql "$url" -X -q -c '\conninfo' 2>&1 | sed -nE 's/.*host "([^"]+)".*/\1/p' | head -n 1
}

tradetraxs_live_project_ref() {
  local url="$1"
  local url_ref host live_ref user_ref
  url_ref="$(_tradetraxs_extract_project_ref_from_url "$url")"
  host="$(tradetraxs_live_db_host "$url")"
  live_ref="$(_tradetraxs_ref_from_db_host "$host")"
  user_ref="$(_tradetraxs_extract_project_ref_from_url "$url")"

  if [[ -n "$live_ref" && -n "$user_ref" && "$live_ref" != "$user_ref" ]]; then
    echo "error: database host ref ($live_ref) != connection URL ref ($user_ref)" >&2
    return 1
  fi
  if [[ -n "$live_ref" ]]; then
    echo "$live_ref"
    return 0
  fi
  if [[ -n "$user_ref" ]]; then
    echo "$user_ref"
    return 0
  fi
  if [[ -n "$url_ref" ]]; then
    echo "$url_ref"
    return 0
  fi
  echo "error: could not determine live project ref (use postgres.<ref> pooler user or db.<ref>.supabase.co host)" >&2
  return 1
}

tradetraxs_assert_not_production_ref() {
  local ref="${1:-}"
  local label="${2:-project ref}"
  if [[ -z "$ref" ]]; then
    echo "error: missing $label" >&2
    exit 1
  fi
  if [[ "$ref" == "$TRADETRAXS_PRODUCTION_PROJECT_REF" ]]; then
    echo "error: $label must not be production ($TRADETRAXS_PRODUCTION_PROJECT_REF)" >&2
    exit 1
  fi
}

tradetraxs_resolve_staging_project_ref() {
  echo "${TRADETRAXS_STAGING_PROJECT_REF:-$TRADETRAXS_ALLOWED_STAGING_PROJECT_REF}"
}

tradetraxs_assert_staging_ref() {
  local ref="${1:-}"
  tradetraxs_assert_not_production_ref "$ref" "staging project ref"
  if [[ "$ref" != "$TRADETRAXS_ALLOWED_STAGING_PROJECT_REF" ]]; then
    echo "error: staging project ref must be $TRADETRAXS_ALLOWED_STAGING_PROJECT_REF (got '$ref')" >&2
    exit 1
  fi
  if [[ -n "${TRADETRAXS_STAGING_PROJECT_REF:-}" && "$TRADETRAXS_STAGING_PROJECT_REF" != "$TRADETRAXS_ALLOWED_STAGING_PROJECT_REF" ]]; then
    echo "error: TRADETRAXS_STAGING_PROJECT_REF ($TRADETRAXS_STAGING_PROJECT_REF) != allowed staging ref ($TRADETRAXS_ALLOWED_STAGING_PROJECT_REF)" >&2
    exit 1
  fi
}

tradetraxs_load_staging_local_env() {
  local env_file
  env_file="$(tradetraxs_staging_root)/.env.local"
  if [[ ! -f "$env_file" ]]; then
    return 0
  fi
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

tradetraxs_production_backup_env_file() {
  echo "$(tradetraxs_staging_root)/full-clone/.env.production.local"
}

tradetraxs_load_production_backup_env() {
  local env_file
  env_file="$(tradetraxs_production_backup_env_file)"
  if [[ ! -f "$env_file" ]]; then
    return 0
  fi
  if grep -E '^[[:space:]]*(TRADETRAXS_ENV|LOADTEST_ENV)=' "$env_file" >/dev/null 2>&1; then
    echo "error: $env_file must not set TRADETRAXS_ENV or LOADTEST_ENV (production backup only)" >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

tradetraxs_assert_production_export_ref() {
  local ref="${1:-}"
  if [[ "$ref" != "$TRADETRAXS_PRODUCTION_PROJECT_REF" ]]; then
    echo "error: export URL must target production ref $TRADETRAXS_PRODUCTION_PROJECT_REF (got '${ref:-empty}')" >&2
    exit 1
  fi
}

tradetraxs_assert_live_database_identity() {
  local expected_ref="$1"
  local db_url="$2"
  local role_label="${3:-database}"

  tradetraxs_prepend_pg_client_path

  if ! command -v psql >/dev/null 2>&1; then
    echo "error: psql required to verify live $role_label identity" >&2
    exit 1
  fi

  local live_ref
  live_ref="$(tradetraxs_live_project_ref "$db_url")"

  if [[ "$live_ref" != "$expected_ref" ]]; then
    echo "error: live $role_label ref '$live_ref' != expected '$expected_ref'" >&2
    exit 1
  fi
}

tradetraxs_assert_staging_live_database() {
  local db_url="$1"
  local staging_ref
  staging_ref="$(tradetraxs_resolve_staging_project_ref)"
  export TRADETRAXS_STAGING_PROJECT_REF="$staging_ref"
  tradetraxs_assert_staging_ref "$staging_ref"
  tradetraxs_assert_live_database_identity "$staging_ref" "$db_url" "staging database"
}

tradetraxs_assert_production_live_database() {
  local db_url="$1"
  local live_ref
  live_ref="$(tradetraxs_live_project_ref "$db_url")"
  tradetraxs_assert_production_export_ref "$live_ref"
  tradetraxs_assert_live_database_identity "$TRADETRAXS_PRODUCTION_PROJECT_REF" "$db_url" "production database"
}

tradetraxs_assert_export_connection_read_only() {
  local db_url="$1"
  local can_create
  can_create="$(psql "$db_url" -X -Atqc "SELECT pg_catalog.has_database_privilege(current_user, current_database(), 'CREATE');" 2>/dev/null || echo "true")"
  if [[ "$can_create" == "t" && "${TRADETRAXS_EXPORT_ALLOW_WRITE_CAPABLE_ROLE:-}" != "yes" ]]; then
    echo "error: export DB role can CREATE in database; use a read-only role or set TRADETRAXS_EXPORT_ALLOW_WRITE_CAPABLE_ROLE=yes to override" >&2
    exit 1
  fi
}

tradetraxs_full_clone_artifact_dir() {
  echo "$(tradetraxs_staging_root)/artifacts/full-clone"
}

tradetraxs_assert_production_session_pooler_url() {
  local url="${TRADETRAXS_PRODUCTION_DATABASE_URL:-}"
  local userpart hostpart
  userpart="$(echo "$url" | sed -E 's#^[a-zA-Z+.-]+://([^:@/]+).*#\1#')"
  hostpart="$(echo "$url" | sed -E 's#.*@([^/:?]+).*#\1#')"

  if [[ "$hostpart" != *".pooler.supabase.com" ]]; then
    echo "error: production backup must use Supabase session pooler (*.pooler.supabase.com), got host '$hostpart'" >&2
    exit 1
  fi
  if [[ "$userpart" != "postgres.${TRADETRAXS_PRODUCTION_PROJECT_REF}" ]]; then
    echo "error: pooler username must be postgres.${TRADETRAXS_PRODUCTION_PROJECT_REF} (got '$userpart')" >&2
    exit 1
  fi
  if [[ "$url" != *sslmode=require* ]]; then
    echo "error: production backup URL must include sslmode=require" >&2
    exit 1
  fi
}

tradetraxs_assert_production_backup_ssl_in_use() {
  local db_url="$1"
  tradetraxs_prepend_pg_client_path
  local ssl_on
  ssl_on="$(psql "$db_url" -X -Atqc "SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();" 2>/dev/null || echo "f")"
  if [[ "$ssl_on" != "t" ]]; then
    echo "error: production backup connection is not using SSL (pg_stat_ssl.ssl=$ssl_on)" >&2
    exit 1
  fi
}

tradetraxs_assert_production_backup_env() {
  if [[ "${TRADETRAXS_ENV:-}" == "staging" || "${LOADTEST_ENV:-}" == "staging" ]]; then
    echo "error: unset TRADETRAXS_ENV/LOADTEST_ENV=staging before production backup" >&2
    exit 1
  fi
  if [[ -z "${TRADETRAXS_PRODUCTION_DATABASE_URL:-}" ]]; then
    echo "error: set TRADETRAXS_PRODUCTION_DATABASE_URL for production backup (shell only; do not commit)" >&2
    exit 1
  fi
  tradetraxs_assert_production_session_pooler_url
  local url_ref
  url_ref="$(tradetraxs_ref_from_url "$TRADETRAXS_PRODUCTION_DATABASE_URL")"
  tradetraxs_assert_production_export_ref "$url_ref"
  tradetraxs_assert_production_live_database "$TRADETRAXS_PRODUCTION_DATABASE_URL"
}

tradetraxs_assert_production_backup_read_only_ops() {
  # pg_dump / supabase db dump issue read-only SELECTs; block explicit write tooling on production URL.
  if [[ "${TRADETRAXS_ALLOW_PRODUCTION_PSQL_WRITES:-}" == "yes" ]]; then
    echo "error: TRADETRAXS_ALLOW_PRODUCTION_PSQL_WRITES=yes is forbidden for TradeTraxs staging tooling" >&2
    exit 1
  fi
}

tradetraxs_assert_full_clone_restore_env() {
  tradetraxs_assert_staging_env
  if [[ -z "${TRADETRAXS_STAGING_DATABASE_URL:-}" ]]; then
    echo "error: set TRADETRAXS_STAGING_DATABASE_URL" >&2
    exit 1
  fi
  if [[ -n "${TRADETRAXS_PRODUCTION_DATABASE_URL:-}" ]]; then
    local prod_ref staging_ref
    prod_ref="$(tradetraxs_ref_from_url "$TRADETRAXS_PRODUCTION_DATABASE_URL")"
    staging_ref="$(tradetraxs_ref_from_url "$TRADETRAXS_STAGING_DATABASE_URL")"
    if [[ "$prod_ref" == "$staging_ref" ]]; then
      echo "error: production and staging database URLs must not be identical" >&2
      exit 1
    fi
  fi
  tradetraxs_assert_staging_live_database "$TRADETRAXS_STAGING_DATABASE_URL"
  if [[ "${TRADETRAXS_FULL_CLONE_CONFIRM:-}" != "yes" ]]; then
    echo "error: set TRADETRAXS_FULL_CLONE_CONFIRM=yes to restore (destructive to staging DB)" >&2
    exit 1
  fi
}

tradetraxs_assert_full_clone_backup_artifacts() {
  local dir
  dir="$(tradetraxs_full_clone_artifact_dir)"
  for f in roles.sql schema.sql data.sql; do
    if [[ ! -s "$dir/$f" ]]; then
      echo "error: missing or empty $dir/$f — run backup-production-database.sh first" >&2
      exit 1
    fi
  done
}

tradetraxs_assert_staging_env() {
  if [[ "${LOADTEST_ENV:-}" != "staging" && "${TRADETRAXS_ENV:-}" != "staging" ]]; then
    echo "error: set LOADTEST_ENV=staging or TRADETRAXS_ENV=staging" >&2
    exit 1
  fi
}

tradetraxs_assert_no_production_host() {
  local url="${1:-}"
  local host
  host="$(echo "$url" | sed -E 's#^https?://([^/]+)/?.*#\1#' | tr '[:upper:]' '[:lower:]')"
  local blocked
  for blocked in "${TRADETRAXS_PRODUCTION_HOSTS[@]}"; do
    if [[ "$host" == "$blocked" || "$host" == *".$blocked" ]]; then
      echo "error: URL host '$host' is blocked (production web)" >&2
      exit 1
    fi
  done
}

tradetraxs_assert_not_service_role_key() {
  local key="${1:-}"
  if [[ -z "$key" ]]; then
    return 0
  fi
  if [[ "$key" == *"service_role"* ]] || [[ "$key" == *"c2VydmljZV9yb2xl"* ]]; then
    echo "error: service_role keys are not allowed for staging bootstrap or load tests" >&2
    exit 1
  fi
}

tradetraxs_ref_from_url() {
  _tradetraxs_extract_project_ref_from_url "$1"
}

_tradetraxs_validate_schema_only_sql() {
  local sql_file="$1"
  local label="$2"
  if [[ ! -f "$sql_file" ]]; then
    echo "error: missing $label $sql_file" >&2
    exit 1
  fi
  if grep -E '^COPY |^\\\\copy |^INSERT INTO ' "$sql_file" >/dev/null 2>&1; then
    echo "error: $label contains row data statements (COPY/INSERT)" >&2
    exit 1
  fi
  if grep -Ei 'insert into auth\.(users|identities|sessions|refresh_tokens)' "$sql_file" >/dev/null 2>&1; then
    echo "error: $label contains Auth identity data statements" >&2
    exit 1
  fi
  if grep -Ei 'insert into (public\.)?(profiles|trades|messages|direct_messages|broker_integration_connections)' "$sql_file" >/dev/null 2>&1; then
    echo "error: $label contains customer table INSERT statements" >&2
    exit 1
  fi
  if grep -Ei 'vault\.secrets|insert into vault' "$sql_file" >/dev/null 2>&1; then
    echo "error: $label references vault secrets data" >&2
    exit 1
  fi
}

tradetraxs_validate_baseline_artifact() {
  _tradetraxs_validate_schema_only_sql "$1" "baseline artifact"
}

tradetraxs_validate_application_artifact() {
  local sql_file="$1"
  _tradetraxs_validate_schema_only_sql "$sql_file" "application schema artifact"
  if ! grep -Ei 'CREATE (OR REPLACE )?FUNCTION public\.handle_new_user' "$sql_file" >/dev/null 2>&1; then
    echo "error: application artifact missing public.handle_new_user()" >&2
    exit 1
  fi
  if grep -Ei '^CREATE TABLE (auth|storage|realtime|graphql_public)\.' "$sql_file" >/dev/null 2>&1; then
    echo "error: application artifact must not CREATE TABLE in Supabase-managed schemas" >&2
    exit 1
  fi
  if grep -Ei '^CREATE SCHEMA (auth|storage|realtime|graphql_public)\b' "$sql_file" >/dev/null 2>&1; then
    echo "error: application artifact must not CREATE SCHEMA for Supabase-managed schemas" >&2
    exit 1
  fi
}

tradetraxs_validate_platform_custom_artifact() {
  local sql_file="$1"
  _tradetraxs_validate_schema_only_sql "$sql_file" "platform custom artifact"
  if ! grep -Ei 'on_auth_user_created' "$sql_file" >/dev/null 2>&1; then
    echo "error: platform custom artifact missing auth.on_auth_user_created trigger" >&2
    exit 1
  fi
  if ! grep -Ei 'CREATE POLICY.*ON storage\.' "$sql_file" >/dev/null 2>&1; then
    echo "error: platform custom artifact missing storage RLS policies" >&2
    exit 1
  fi
  if grep -Ei '^CREATE TABLE (auth|storage|realtime|graphql_public)\.' "$sql_file" >/dev/null 2>&1; then
    echo "error: platform custom artifact must not CREATE TABLE in Supabase-managed schemas" >&2
    exit 1
  fi
  if grep -Ei '^CREATE SCHEMA (auth|storage|realtime|graphql_public)\b' "$sql_file" >/dev/null 2>&1; then
    echo "error: platform custom artifact must not CREATE SCHEMA for Supabase-managed schemas" >&2
    exit 1
  fi
}

tradetraxs_validate_staging_export_artifacts() {
  local app_sql="$1"
  local platform_sql="$2"
  tradetraxs_validate_application_artifact "$app_sql"
  tradetraxs_validate_platform_custom_artifact "$platform_sql"
}

tradetraxs_write_verification_stamp() {
  local project_ref="$1"
  local mode="$2"
  local stamp
  stamp="$(tradetraxs_verification_stamp_path)"
  mkdir -p "$(dirname "$stamp")"
  python3 - "$stamp" "$project_ref" "$mode" <<'PY'
import json, sys
from datetime import datetime, timezone

path, ref, mode = sys.argv[1:4]
if mode not in ("baseline", "forward", "all"):
    raise SystemExit(f"error: invalid verification mode {mode}")

doc = {}
try:
    with open(path) as f:
        doc = json.load(f)
except FileNotFoundError:
    pass

prev_ref = doc.get("project_ref")
if prev_ref and prev_ref != ref:
    raise SystemExit(f"error: stamp project_ref mismatch ({prev_ref} vs {ref})")

baseline = doc.get("baseline_verified", False)
forward = doc.get("forward_verified", False)

if mode in ("baseline", "all"):
    baseline = True
if mode == "forward":
    if not baseline:
        raise SystemExit("error: baseline verification required before forward verify")
    forward = True
if mode == "all":
    forward = True

doc.update({
    "project_ref": ref,
    "baseline_verified": baseline,
    "forward_verified": forward,
    "verified_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
})
with open(path, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
  chmod 600 "$stamp" 2>/dev/null || true
}

tradetraxs_assert_verification_stamp() {
  local expected_ref="$1"
  local require_forward="${2:-no}"
  local stamp
  stamp="$(tradetraxs_verification_stamp_path)"
  if [[ ! -f "$stamp" ]]; then
    echo "error: missing verification stamp ($stamp); run run-verify.sh first" >&2
    exit 1
  fi
  python3 - "$stamp" "$expected_ref" "$require_forward" <<'PY'
import json, sys
path, expected_ref, require_forward = sys.argv[1:4]
with open(path) as f:
    doc = json.load(f)
if doc.get("project_ref") != expected_ref:
    raise SystemExit(f"error: stamp project_ref {doc.get('project_ref')!r} != expected {expected_ref!r}")
if not doc.get("baseline_verified"):
    raise SystemExit("error: baseline_verified is false in stamp")
if require_forward == "yes" and not doc.get("forward_verified"):
    raise SystemExit("error: forward_verified required but false in stamp")
PY
}

tradetraxs_assert_seed_file_safe() {
  local seed_file="$1"
  if grep -E ':[A-Z0-9_]+:' "$seed_file" | grep -Ev '^[[:space:]]*--' >/dev/null 2>&1; then
    echo "error: seed file contains unresolved :PLACEHOLDER: tokens in active SQL" >&2
    exit 1
  fi
  if grep -E '^[[:space:]]*(insert|update|delete|truncate)' "$seed_file" >/dev/null 2>&1; then
    echo "error: seed file contains active writes; keep inserts commented until placeholders are replaced" >&2
    exit 1
  fi
}

tradetraxs_assert_cli_not_linked_to_production() {
  local root="${1:-}"
  local link_file ref
  for link_file in "$root/.supabase/project-ref" "$root/supabase/.temp/project-ref"; do
    if [[ -f "$link_file" ]]; then
      ref="$(tr -d '[:space:]' < "$link_file")"
      if [[ "$ref" == "$TRADETRAXS_PRODUCTION_PROJECT_REF" ]]; then
        echo "error: Supabase CLI is linked to production ($link_file); unlink or use --project-ref without linking" >&2
        exit 1
      fi
    fi
  done
}

tradetraxs_forward_manifest_has_apply_lines() {
  local manifest="$1"
  grep -v '^[[:space:]]*#' "$manifest" | grep -v '^[[:space:]]*skip:' | grep -E '^supabase/migrations/' >/dev/null 2>&1
}
