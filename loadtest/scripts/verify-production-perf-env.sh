#!/usr/bin/env bash
# Verify loadtest/.env.production-perf structure without printing secret values.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/loadtest/.env.production-perf"
CONFIG_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --config-only) CONFIG_ONLY=1 ;;
  esac
done
if [[ "${LOADTEST_VERIFY_CONFIG_ONLY:-}" == "yes" ]]; then
  CONFIG_ONLY=1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: missing $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

required_vars=(
  LOADTEST_ENV
  TRADETRAXS_PROD_PERF_CONFIRM
  TRADETRAXS_PRODUCTION_PROJECT_REF
  LOADTEST_PROD_PERF_MODE
  LOADTEST_MAX_VUS
  LOADTEST_SUPABASE_URL
  LOADTEST_SUPABASE_ANON_KEY
  LOADTEST_WEB_URL
  LOADTEST_USERS_JSON
)

for v in "${required_vars[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "error: $v is empty (after sourcing $ENV_FILE)" >&2
    exit 1
  fi
done

[[ "$LOADTEST_ENV" == "production" ]] || { echo "error: LOADTEST_ENV must be production" >&2; exit 1; }
[[ "$TRADETRAXS_PROD_PERF_CONFIRM" == "yes" ]] || { echo "error: TRADETRAXS_PROD_PERF_CONFIRM must be yes" >&2; exit 1; }
[[ "$TRADETRAXS_PRODUCTION_PROJECT_REF" == "fobudrkniacatvilbofw" ]] || { echo "error: wrong production ref" >&2; exit 1; }
case "$LOADTEST_PROD_PERF_MODE" in
  smoke)
    [[ "$LOADTEST_MAX_VUS" == "1" ]] || { echo "error: LOADTEST_MAX_VUS must be 1 for smoke" >&2; exit 1; }
    ;;
  full)
    [[ "$LOADTEST_MAX_VUS" == "5" ]] || { echo "error: LOADTEST_MAX_VUS must be 5 for full" >&2; exit 1; }
    [[ "${TRADETRAXS_PROD_PERF_FULL:-}" == "yes" ]] || { echo "error: TRADETRAXS_PROD_PERF_FULL must be yes for full mode" >&2; exit 1; }
    ;;
  ten)
    [[ "$LOADTEST_MAX_VUS" == "10" ]] || { echo "error: LOADTEST_MAX_VUS must be 10 for ten mode" >&2; exit 1; }
    [[ "${TRADETRAXS_PROD_PERF_TEN:-}" == "yes" ]] || { echo "error: TRADETRAXS_PROD_PERF_TEN must be yes for ten mode" >&2; exit 1; }
    ;;
  twentyfive)
    [[ "$LOADTEST_MAX_VUS" == "25" ]] || { echo "error: LOADTEST_MAX_VUS must be 25 for twentyfive mode" >&2; exit 1; }
    [[ "${TRADETRAXS_PROD_PERF_TWENTYFIVE:-}" == "yes" ]] || { echo "error: TRADETRAXS_PROD_PERF_TWENTYFIVE must be yes for twentyfive mode" >&2; exit 1; }
    ;;
  fifty)
    [[ "$LOADTEST_MAX_VUS" == "50" ]] || { echo "error: LOADTEST_MAX_VUS must be 50 for fifty mode" >&2; exit 1; }
    [[ "${TRADETRAXS_PROD_PERF_FIFTY:-}" == "yes" ]] || { echo "error: TRADETRAXS_PROD_PERF_FIFTY must be yes for fifty mode" >&2; exit 1; }
    ;;
  seventyfive)
    [[ "$LOADTEST_MAX_VUS" == "75" ]] || { echo "error: LOADTEST_MAX_VUS must be 75 for seventyfive mode" >&2; exit 1; }
    [[ "${TRADETRAXS_PROD_PERF_SEVENTYFIVE:-}" == "yes" ]] || { echo "error: TRADETRAXS_PROD_PERF_SEVENTYFIVE must be yes for seventyfive mode" >&2; exit 1; }
    ;;
  hundred)
    [[ "$LOADTEST_MAX_VUS" == "100" ]] || { echo "error: LOADTEST_MAX_VUS must be 100 for hundred mode" >&2; exit 1; }
    [[ "${TRADETRAXS_PROD_PERF_HUNDRED:-}" == "yes" ]] || { echo "error: TRADETRAXS_PROD_PERF_HUNDRED must be yes for hundred mode" >&2; exit 1; }
    ;;
  onefifty)
    [[ "$LOADTEST_MAX_VUS" == "150" ]] || { echo "error: LOADTEST_MAX_VUS must be 150 for onefifty mode" >&2; exit 1; }
    [[ "${TRADETRAXS_PROD_PERF_ONEFIFTY:-}" == "yes" ]] || { echo "error: TRADETRAXS_PROD_PERF_ONEFIFTY must be yes for onefifty mode" >&2; exit 1; }
    ;;
  realistic150)
    [[ "$LOADTEST_MAX_VUS" == "150" ]] || { echo "error: LOADTEST_MAX_VUS must be 150 for realistic150 mode" >&2; exit 1; }
    [[ "${TRADETRAXS_PROD_PERF_REALISTIC150:-}" == "yes" ]] || {
      echo "error: TRADETRAXS_PROD_PERF_REALISTIC150 must be yes for realistic150 mode" >&2
      exit 1
    }
    ;;
  realistic300)
    [[ "$LOADTEST_MAX_VUS" == "300" ]] || { echo "error: LOADTEST_MAX_VUS must be 300 for realistic300 mode" >&2; exit 1; }
    [[ "${TRADETRAXS_PROD_PERF_REALISTIC300:-}" == "yes" ]] || {
      echo "error: TRADETRAXS_PROD_PERF_REALISTIC300 must be yes for realistic300 mode" >&2
      exit 1
    }
    ;;
  *)
    echo "error: LOADTEST_PROD_PERF_MODE must be smoke, full, ten, twentyfive, fifty, seventyfive, hundred, onefifty, realistic150, or realistic300" >&2
    exit 1
    ;;
esac

if [[ "$LOADTEST_SUPABASE_URL" != *"fobudrkniacatvilbofw"* ]]; then
  echo "error: LOADTEST_SUPABASE_URL must contain production project ref" >&2
  exit 1
fi

PLACEHOLDER=0

anon="$LOADTEST_SUPABASE_ANON_KEY"
case "$anon" in
  REPLACE_WITH_PRODUCTION_ANON_OR_PUBLISHABLE_KEY | your_production_anon_key)
    echo "pending: set LOADTEST_SUPABASE_ANON_KEY in $ENV_FILE" >&2
    PLACEHOLDER=1
    ;;
esac
if [[ ${#anon} -lt 20 ]]; then
  echo "pending: LOADTEST_SUPABASE_ANON_KEY looks too short after sourcing $ENV_FILE" >&2
  PLACEHOLDER=1
fi

if [[ "${anon}" == *service_role* ]] || [[ "${anon}" == *c2VydmljZV9yb2xl* ]]; then
  echo "error: anon key must not be service_role" >&2
  exit 1
fi

python3 - <<'PY' "$LOADTEST_USERS_JSON" "$LOADTEST_PROD_PERF_MODE" "$LOADTEST_MAX_VUS"
import json, os, sys

raw = sys.argv[1]
mode = sys.argv[2]
max_vus = int(sys.argv[3])
PLACEHOLDER_EMAIL = "REPLACE_WITH_PERF_TEST_EMAIL"
PLACEHOLDER_PASSWORD = "REPLACE_WITH_PERF_TEST_PASSWORD"

try:
    data = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(
        "error: LOADTEST_USERS_JSON is not valid JSON after sourcing env file "
        "(use single quotes around the whole value in loadtest/.env.production-perf)"
    )

if not isinstance(data, list) or len(data) == 0:
    raise SystemExit("error: LOADTEST_USERS_JSON must be a non-empty array")

if len(data) > max_vus:
    raise SystemExit(f"error: {mode} allows at most {max_vus} users (got {len(data)})")

if mode == "smoke" and len(data) != 1:
    raise SystemExit("error: smoke requires exactly one user in LOADTEST_USERS_JSON")

for u in data:
    email = (u.get("email") or "").strip()
    password = u.get("password") or ""
    if not email or not password:
        raise SystemExit("error: each user needs email and password")
    if email == PLACEHOLDER_EMAIL or password == PLACEHOLDER_PASSWORD:
        raise SystemExit("pending: set perf test email/password in LOADTEST_USERS_JSON")
    if email.startswith("REPLACE_WITH_") or password.startswith("REPLACE_WITH_"):
        raise SystemExit("pending: LOADTEST_USERS_JSON still uses REPLACE_WITH_* placeholders")
PY

if [[ "${PLACEHOLDER:-0}" == "1" ]]; then
  exit 2
fi

WORKLOAD_KIND="${LOADTEST_WORKLOAD_KIND:-supabase_direct}"
case "$WORKLOAD_KIND" in
  supabase_direct | client_realistic | realistic150_ios) ;;
  *)
    echo "error: LOADTEST_WORKLOAD_KIND must be supabase_direct, client_realistic, or realistic150_ios" >&2
    exit 1
    ;;
esac

FEED_SCOPE="${LOADTEST_FEED_SCOPE:-}"
if [[ -n "$FEED_SCOPE" ]] && [[ "$FEED_SCOPE" != "following" ]] && [[ "$FEED_SCOPE" != "global" ]]; then
  echo "error: LOADTEST_FEED_SCOPE must be following or global when set" >&2
  exit 1
fi

USER_COUNT="$(python3 - <<'PY' "$LOADTEST_USERS_JSON"
import json, sys
print(len(json.loads(sys.argv[1])))
PY
)"

if [[ "$WORKLOAD_KIND" == "client_realistic" ]] && [[ "$LOADTEST_PROD_PERF_MODE" != "smoke" ]]; then
  RECOMMENDED=$(( LOADTEST_MAX_VUS / 5 ))
  if [[ "$RECOMMENDED" -lt 2 ]]; then RECOMMENDED=2; fi
  if [[ "$USER_COUNT" -lt "$RECOMMENDED" ]]; then
    echo "warn: client_realistic recommends >= $RECOMMENDED dedicated users for $LOADTEST_MAX_VUS VUs (have $USER_COUNT); VUs will share accounts via round-robin" >&2
  fi
  if [[ "$LOADTEST_PROD_PERF_MODE" == "twentyfive" || "$LOADTEST_PROD_PERF_MODE" == "fifty" ]] && [[ "$USER_COUNT" -lt 5 ]]; then
    echo "error: ${LOADTEST_PROD_PERF_MODE} + client_realistic requires >= 5 dedicated users (have $USER_COUNT); one shared account duplicates cache-miss RPCs and invalidates results (see loadtest/PRODUCTION_READ_PERF.md)" >&2
    exit 1
  fi
fi

if [[ "$LOADTEST_PROD_PERF_MODE" == "seventyfive" || "$LOADTEST_PROD_PERF_MODE" == "hundred" ]] && [[ "$USER_COUNT" -lt 30 ]]; then
  echo "error: ${LOADTEST_PROD_PERF_MODE} mode requires >= 30 dedicated users in LOADTEST_USERS_JSON (have $USER_COUNT)" >&2
  exit 1
fi

if [[ "$LOADTEST_PROD_PERF_MODE" == "onefifty" || "$LOADTEST_PROD_PERF_MODE" == "realistic150" || "$LOADTEST_PROD_PERF_MODE" == "realistic300" ]] && [[ "$USER_COUNT" -ne 50 ]]; then
  echo "error: ${LOADTEST_PROD_PERF_MODE} mode requires exactly 50 dedicated users in LOADTEST_USERS_JSON (have $USER_COUNT)" >&2
  echo "hint: tradetraxsdemo@gmail.com + tradetraxsdemo+perfload02 … perfload50 (see loadtest/docs/PROD_PERF_ONEFIFTY_FIFTY_USERS.md)" >&2
  exit 1
fi

python3 - <<'PY' "$LOADTEST_USERS_JSON"
import json, sys
users = json.loads(sys.argv[1])
emails = [(u.get("email") or "").strip().lower() for u in users]
if len(emails) != len(set(emails)):
    raise SystemExit("error: LOADTEST_USERS_JSON contains duplicate emails")
PY

if [[ "$CONFIG_ONLY" == "1" ]]; then
  echo "config-only: skipping preflight-prod-perf-auth (no password grants)" >&2
elif [[ "$LOADTEST_PROD_PERF_MODE" == "onefifty" || "$LOADTEST_PROD_PERF_MODE" == "realistic150" || "$LOADTEST_PROD_PERF_MODE" == "realistic300" ]] && [[ "$USER_COUNT" -eq 50 ]]; then
  echo "${LOADTEST_PROD_PERF_MODE}: verifying 50 account password grants (read-only auth)..." >&2
  "$ROOT/loadtest/scripts/preflight-prod-perf-auth.sh"
fi

if ! command -v k6 >/dev/null 2>&1; then
  echo "error: k6 not installed (brew install k6)" >&2
  exit 1
fi

if [[ "$CONFIG_ONLY" == "1" ]]; then
  echo "ok: config-only env structure, mode=$LOADTEST_PROD_PERF_MODE max_vus=$LOADTEST_MAX_VUS workload=$WORKLOAD_KIND users=$USER_COUNT (file: $ENV_FILE)"
else
  echo "ok: env structure, mode=$LOADTEST_PROD_PERF_MODE max_vus=$LOADTEST_MAX_VUS workload=$WORKLOAD_KIND users=$USER_COUNT, production ref (file: $ENV_FILE)"
fi
k6 version | head -1
