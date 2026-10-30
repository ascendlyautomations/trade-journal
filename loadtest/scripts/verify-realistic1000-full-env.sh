#!/usr/bin/env bash
# Validate realistic1000_full env + fixture without password-grant auth (avoids Auth 429 before k6 setup).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${LOADTEST_ENV_FILE:-$ROOT/loadtest/.env.production-perf}"
CONFIG_ONLY=0
REQUIRED_MAX_VUS=1000

for arg in "$@"; do
  case "$arg" in
    --config-only) CONFIG_ONLY=1 ;;
    -h | --help)
      echo "Usage: $0 [--config-only]" >&2
      echo "  Validates TRADETRAXS_PROD_PERF_REALISTIC1000_FULL=yes and LOADTEST_MAX_VUS=1000." >&2
      exit 0
      ;;
  esac
done

if [[ "${LOADTEST_VERIFY_CONFIG_ONLY:-}" == "yes" ]]; then
  CONFIG_ONLY=1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: missing env file: $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

[[ "${LOADTEST_ENV:-}" == "production" ]] || {
  echo "error: LOADTEST_ENV must be production" >&2
  exit 1
}
[[ "${TRADETRAXS_PROD_PERF_CONFIRM:-}" == "yes" ]] || {
  echo "error: TRADETRAXS_PROD_PERF_CONFIRM must be yes" >&2
  exit 1
}
[[ "${TRADETRAXS_PROD_PERF_REALISTIC1000_FULL:-}" == "yes" ]] || {
  echo "error: TRADETRAXS_PROD_PERF_REALISTIC1000_FULL must be yes" >&2
  exit 1
}
[[ "${TRADETRAXS_PROD_PERF_REALISTIC600_FULL:-}" != "yes" ]] || {
  echo "error: unset TRADETRAXS_PROD_PERF_REALISTIC600_FULL for realistic1000_full" >&2
  exit 1
}
[[ "${LOADTEST_MAX_VUS:-}" == "$REQUIRED_MAX_VUS" ]] || {
  echo "error: LOADTEST_MAX_VUS must be $REQUIRED_MAX_VUS for realistic1000_full" >&2
  exit 1
}

FIXTURE_JSON="${LOADTEST_REALISTIC1000_FULL_FIXTURE_JSON:-}"
if [[ -z "$FIXTURE_JSON" && -n "${LOADTEST_REALISTIC1000_FULL_FIXTURE_FILE:-}" ]]; then
  if [[ ! -f "$LOADTEST_REALISTIC1000_FULL_FIXTURE_FILE" ]]; then
    echo "error: LOADTEST_REALISTIC1000_FULL_FIXTURE_FILE not found: $LOADTEST_REALISTIC1000_FULL_FIXTURE_FILE" >&2
    exit 1
  fi
  FIXTURE_JSON="$(cat "$LOADTEST_REALISTIC1000_FULL_FIXTURE_FILE")"
  export LOADTEST_REALISTIC1000_FULL_FIXTURE_JSON="$FIXTURE_JSON"
fi
if [[ -z "$FIXTURE_JSON" ]]; then
  FIXTURE_JSON="${LOADTEST_REALISTIC600_FULL_FIXTURE_JSON:-}"
  if [[ -z "$FIXTURE_JSON" && -n "${LOADTEST_REALISTIC600_FULL_FIXTURE_FILE:-}" ]]; then
    if [[ ! -f "$LOADTEST_REALISTIC600_FULL_FIXTURE_FILE" ]]; then
      echo "error: LOADTEST_REALISTIC600_FULL_FIXTURE_FILE not found: $LOADTEST_REALISTIC600_FULL_FIXTURE_FILE" >&2
      exit 1
    fi
    FIXTURE_JSON="$(cat "$LOADTEST_REALISTIC600_FULL_FIXTURE_FILE")"
    export LOADTEST_REALISTIC600_FULL_FIXTURE_JSON="$FIXTURE_JSON"
  fi
fi
if [[ -z "$FIXTURE_JSON" ]]; then
  echo "error: set LOADTEST_REALISTIC1000_FULL_FIXTURE_* or LOADTEST_REALISTIC600_FULL_FIXTURE_* (same fixture)" >&2
  exit 1
fi

[[ "${LOADTEST_FULL_MESSAGE_TAG:-}" == "[loadtest:realistic1000_full]" ]] || {
  echo 'error: LOADTEST_FULL_MESSAGE_TAG must be [loadtest:realistic1000_full] for realistic1000_full' >&2
  exit 1
}

if [[ "$LOADTEST_SUPABASE_URL" != *"fobudrkniacatvilbofw"* ]]; then
  echo "error: LOADTEST_SUPABASE_URL must contain production project ref" >&2
  exit 1
fi

anon="${LOADTEST_SUPABASE_ANON_KEY:-}"
if [[ -z "$anon" ]]; then
  echo "error: LOADTEST_SUPABASE_ANON_KEY is empty" >&2
  exit 1
fi
if [[ "${anon}" == *service_role* ]] || [[ "${anon}" == *c2VydmljZV9yb2xl* ]]; then
  echo "error: anon key must not be service_role" >&2
  exit 1
fi

if [[ -z "${LOADTEST_REALISTIC600_USERS_JSON:-}" ]]; then
  echo "error: missing LOADTEST_REALISTIC600_USERS_JSON (100 perf accounts)" >&2
  exit 1
fi

USER_COUNT="$(python3 - <<'PY' "$LOADTEST_REALISTIC600_USERS_JSON"
import json, sys
print(len(json.loads(sys.argv[1])))
PY
)"
[[ "$USER_COUNT" == "100" ]] || {
  echo "error: realistic1000_full requires exactly 100 users in LOADTEST_REALISTIC600_USERS_JSON (have $USER_COUNT)" >&2
  exit 1
}

export LOADTEST_MAX_VUS="${LOADTEST_MAX_VUS:-1000}"
python3 - <<'PY' "$FIXTURE_JSON" "$LOADTEST_REALISTIC600_USERS_JSON"
import json, os, re, sys

UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    re.I,
)

fixture = json.loads(sys.argv[1])
users = json.loads(sys.argv[2])
if fixture.get("schemaVersion") != 1:
    raise SystemExit("error: fixture schemaVersion must be 1")
tag = fixture.get("tag") or ""
if "loadtest" not in tag.lower():
    raise SystemExit("error: fixture tag must identify loadtest isolation")

emails = {(u.get("email") or "").strip().lower() for u in users}
participants = set()
for c in fixture.get("directConversations") or []:
    cid = (c.get("id") or "").strip()
    if not UUID_RE.match(cid):
        raise SystemExit(f"error: invalid directConversations id (uuid expected): {cid[:40]}")
    for e in c.get("participantEmails") or []:
        participants.add(e.strip().lower())
for r in fixture.get("tradeRooms") or []:
    rid = (r.get("id") or "").strip()
    if not UUID_RE.match(rid):
        raise SystemExit(f"error: invalid tradeRooms id (uuid expected): {rid[:40]}")
    sec = r.get("sectionId")
    if sec is not None and str(sec).strip() and not UUID_RE.match(str(sec).strip()):
        raise SystemExit("error: tradeRooms.sectionId must be uuid or null")
    for e in r.get("memberEmails") or []:
        participants.add(e.strip().lower())
if not participants:
    raise SystemExit("error: fixture has no participants")
missing = sorted(participants - emails)
if missing:
    raise SystemExit(
        "error: fixture references emails not in LOADTEST_REALISTIC600_USERS_JSON: "
        + ", ".join(missing[:5])
    )
not_in_fixture = sorted(emails - participants)
if not_in_fixture:
    raise SystemExit(
        "error: these LOADTEST_REALISTIC600_USERS_JSON emails are not fixture participants: "
        + ", ".join(not_in_fixture[:8])
    )
if len(emails) != 100:
    raise SystemExit(f"error: expected 100 distinct user emails, got {len(emails)}")

def parse_cap(name, required):
    raw = os.environ.get(name, "").strip()
    if not raw:
        raise SystemExit(f"error: {name} must be set to {required} for realistic1000_full")
    try:
        n = int(raw)
    except ValueError:
        raise SystemExit(f"error: {name} must be a non-negative integer (got {raw!r})")
    if n != required:
        raise SystemExit(f"error: {name} must be {required} for realistic1000_full (got {n})")
    return n

max_vus = int(os.environ.get("LOADTEST_MAX_VUS", "1000"))
dm_total = parse_cap("LOADTEST_FULL_MAX_DM_SENDS_TOTAL", 700)
room_total = parse_cap("LOADTEST_FULL_MAX_ROOM_SENDS_TOTAL", 700)

push = os.environ.get("LOADTEST_FULL_SKIP_PUSH", "yes").strip().lower()
if push not in ("yes", "no"):
    raise SystemExit("error: LOADTEST_FULL_SKIP_PUSH must be yes or no")
if push == "no":
    print("warn: LOADTEST_FULL_SKIP_PUSH=no — push notify may reach real devices", file=sys.stderr)

def vu_allowance(global_cap, vus, vu_id):
    base, rem = divmod(global_cap, vus)
    return base + (1 if vu_id <= rem else 0)

def partition_sum(cap, vus):
    return sum(vu_allowance(cap, vus, vu) for vu in range(1, vus + 1))

if partition_sum(dm_total, max_vus) != dm_total:
    raise SystemExit("internal: dm partition sum mismatch")
if partition_sum(room_total, max_vus) != room_total:
    raise SystemExit("internal: room partition sum mismatch")

# Spot-check 1000-VU partitioning (700 cap → VUs 1–700 get 1 send, 701–1000 get 0)
for vu, expected in ((1, 1), (700, 1), (701, 0), (1000, 0)):
    got = vu_allowance(dm_total, max_vus, vu)
    if got != expected:
        raise SystemExit(f"error: vu {vu} dm allowance expected {expected}, got {got}")

print(
    f"caps: dm_total={dm_total} room_total={room_total} message_sends_total={dm_total + room_total} "
    f"max_vus={max_vus} vu_distribution=10_per_account (100 accounts)"
)
PY

if [[ "${LOADTEST_FULL_SKIP_PUSH:-yes}" == "no" ]]; then
  echo "warn: LOADTEST_FULL_SKIP_PUSH=no — not recommended on production" >&2
fi

if ! command -v k6 >/dev/null 2>&1; then
  echo "error: k6 not installed (brew install k6)" >&2
  exit 1
fi

FD_LIMIT="$(ulimit -n 2>/dev/null || echo 0)"
if [[ "$FD_LIMIT" != "unlimited" && "$FD_LIMIT" -lt 10240 ]]; then
  echo "warn: ulimit -n is $FD_LIMIT — recommend >= 10240 for 1000 VUs + WebSockets (try: ulimit -n 65536)" >&2
fi

if [[ "$CONFIG_ONLY" == "1" ]]; then
  echo "ok: realistic1000_full config-only (no Auth HTTP) file=$ENV_FILE users=$USER_COUNT"
else
  echo "ok: realistic1000_full env (file: $ENV_FILE) users=$USER_COUNT fixture validated"
fi
k6 version | head -1
