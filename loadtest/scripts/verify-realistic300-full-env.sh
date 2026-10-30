#!/usr/bin/env bash
# Validate realistic300_full env + fixture without password-grant auth (avoids Auth 429 before k6 setup).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${LOADTEST_ENV_FILE:-$ROOT/loadtest/.env.production-perf}"
CONFIG_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --config-only) CONFIG_ONLY=1 ;;
    -h | --help)
      echo "Usage: $0 [--config-only]" >&2
      echo "  --config-only  Validate env, fixture, and safety caps only (no Auth HTTP)." >&2
      echo "  Or set LOADTEST_VERIFY_CONFIG_ONLY=yes" >&2
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
[[ "${TRADETRAXS_PROD_PERF_REALISTIC300_FULL:-}" == "yes" ]] || {
  echo "error: TRADETRAXS_PROD_PERF_REALISTIC300_FULL must be yes" >&2
  exit 1
}
[[ "${LOADTEST_MAX_VUS:-}" == "300" ]] || {
  echo "error: LOADTEST_MAX_VUS must be 300" >&2
  exit 1
}

FIXTURE_JSON="${LOADTEST_REALISTIC300_FULL_FIXTURE_JSON:-}"
if [[ -z "$FIXTURE_JSON" && -n "${LOADTEST_REALISTIC300_FULL_FIXTURE_FILE:-}" ]]; then
  if [[ ! -f "$LOADTEST_REALISTIC300_FULL_FIXTURE_FILE" ]]; then
    echo "error: LOADTEST_REALISTIC300_FULL_FIXTURE_FILE not found: $LOADTEST_REALISTIC300_FULL_FIXTURE_FILE" >&2
    exit 1
  fi
  FIXTURE_JSON="$(cat "$LOADTEST_REALISTIC300_FULL_FIXTURE_FILE")"
  export LOADTEST_REALISTIC300_FULL_FIXTURE_JSON="$FIXTURE_JSON"
fi
if [[ -z "$FIXTURE_JSON" ]]; then
  echo "error: set LOADTEST_REALISTIC300_FULL_FIXTURE_JSON or LOADTEST_REALISTIC300_FULL_FIXTURE_FILE" >&2
  echo "hint: provision per loadtest/docs/REALISTIC300_FULL_FIXTURE_PROVISION_STEPS.md then:" >&2
  echo "  node loadtest/scripts/discover-realistic300-full-fixture.mjs" >&2
  exit 1
fi

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

USER_COUNT="$(python3 - <<'PY' "$LOADTEST_USERS_JSON"
import json, sys
print(len(json.loads(sys.argv[1])))
PY
)"
[[ "$USER_COUNT" == "50" ]] || {
  echo "error: realistic300_full requires exactly 50 users (have $USER_COUNT)" >&2
  exit 1
}

export LOADTEST_MAX_VUS="${LOADTEST_MAX_VUS:-300}"
python3 - <<'PY' "$FIXTURE_JSON" "$LOADTEST_USERS_JSON"
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
    raise SystemExit("error: fixture references emails not in LOADTEST_USERS_JSON: " + ", ".join(missing[:5]))
not_in_fixture = sorted(emails - participants)
if not_in_fixture:
    raise SystemExit(
        "error: these LOADTEST_USERS_JSON emails are not fixture participants: "
        + ", ".join(not_in_fixture[:8])
    )
if "REPLACE_WITH" in sys.argv[1]:
    raise SystemExit("pending: fixture still contains REPLACE_WITH placeholders")

def parse_cap(name, default):
    raw = os.environ.get(name, str(default)).strip()
    try:
        n = int(raw)
    except ValueError:
        raise SystemExit(f"error: {name} must be a non-negative integer (got {raw!r})")
    if n < 0:
        raise SystemExit(f"error: {name} must be >= 0")
    return n

max_vus = int(os.environ.get("LOADTEST_MAX_VUS", "300"))
dm_total = parse_cap("LOADTEST_FULL_MAX_DM_SENDS_TOTAL", 200)
room_total = parse_cap("LOADTEST_FULL_MAX_ROOM_SENDS_TOTAL", 200)
if dm_total > 5000 or room_total > 5000:
    raise SystemExit("error: global send caps above 5000 require explicit ops approval (lower LOADTEST_FULL_MAX_*_SENDS_TOTAL)")

push = os.environ.get("LOADTEST_FULL_SKIP_PUSH", "yes").strip().lower()
if push not in ("yes", "no"):
    raise SystemExit("error: LOADTEST_FULL_SKIP_PUSH must be yes or no")
if push == "no":
    print("warn: LOADTEST_FULL_SKIP_PUSH=no — push notify may reach real devices if wired", file=sys.stderr)

# Partition sanity (same formula as k6)
def partition_sum(cap, vus):
    base, rem = divmod(cap, vus)
    return rem * (base + 1) + (vus - rem) * base

if partition_sum(dm_total, max_vus) != dm_total:
    raise SystemExit("internal: dm partition sum mismatch")
if partition_sum(room_total, max_vus) != room_total:
    raise SystemExit("internal: room partition sum mismatch")

print(
    f"caps: dm_total={dm_total} room_total={room_total} max_vus={max_vus} "
    f"(vu1 allowance dm={dm_total // max_vus + (1 if dm_total % max_vus else 0)} …)"
)
PY

if [[ "${LOADTEST_FULL_SKIP_PUSH:-yes}" == "no" ]]; then
  echo "warn: LOADTEST_FULL_SKIP_PUSH=no — not recommended on production" >&2
fi

if ! command -v k6 >/dev/null 2>&1; then
  echo "error: k6 not installed (brew install k6)" >&2
  exit 1
fi

if [[ "$CONFIG_ONLY" == "1" ]]; then
  echo "ok: realistic300_full config-only (no Auth HTTP) file=$ENV_FILE users=$USER_COUNT"
else
  echo "ok: realistic300_full env (file: $ENV_FILE) users=$USER_COUNT fixture validated (use --config-only to skip future auth checks)"
fi
k6 version | head -1
