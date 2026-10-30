# Realistic300_full — iOS reads + messaging + Realtime

**Separate script:** `loadtest/prod-realistic300-full.js` — does **not** modify `prod-read-perf.js` modes (`onefifty`, `realistic150`, `realistic300`, etc.).

Simulates **300 concurrent virtual sessions** on **50 authenticated perf accounts** with:

- Same read mix as `realistic150` (~85%): Feed, Dashboard, Profile/Trades, Calendar, passive view, idle (screen TTL cache, 10–60s think, 60–180s idle)
- ~15% messaging/Realtime: DM inbox/thread, trade-room inbox/thread, notifications Realtime watch
- Occasional **tagged** DM/room **writes** (not every iteration)
- Short-lived **WebSocket** sessions mirroring iOS Phoenix joins (`realtime:dm-*`, `realtime:room-live-*`, inbox routes)

Audit reference: **`loadtest/docs/IOS_MESSAGING_REALTIME_AUDIT.md`**

## Sessions vs accounts

| | Value |
|--|--------|
| Concurrent VUs | **300** |
| JWT accounts | **50** (required) |
| Mapping | Pseudo-random stable VU→user (~**6** sessions per account on average) |

**300 sessions ≠ 300 unique humans.**

## Safety (required)

1. **Isolation fixture** — `LOADTEST_REALISTIC300_FULL_FIXTURE_JSON` lists only perf-owned `directConversations` and `tradeRooms`. Setup **refuses** users not listed as fixture participants.
2. **Tagged writes** — message body prefix `[loadtest:realistic300_full]` for cleanup.
3. **No push by default** — `LOADTEST_FULL_SKIP_PUSH=yes` (default); harness does **not** call `/api/messaging/notify-dm` or room notify APIs.
4. **Send caps** — **global** (default **200** DM + **200** room total across all 300 VUs), enforced by deterministic per-VU partition (race-free in k6). Optional tighter `LOADTEST_FULL_MAX_*_SENDS_PER_VU` ceiling per VU.
5. **Never** message real users — fixture must only pair perf emails; see provisioning plan.
6. **Cleanup** — run `loadtest/scripts/cleanup-realistic300-full-data.mjs` after the test.

## Excluded / limitations

| Included | Not in harness |
|----------|----------------|
| PostgREST reads (feed, dashboard, …) | Media/CDN downloads |
| `rpc_v2_messaging_bootstrap`, thread bootstrap | DM typing **broadcast** (web-only) |
| Realtime `postgres_changes` | Room **presence** track |
| Tagged DM + room text inserts | Trade share / voice / image messages |
| | Billing, broker, leaderboard |
| | Enabling push (`LOADTEST_FULL_SKIP_PUSH=no`) without ops review |

## Executor

`ramping-vus`: **3m → 300**, **10m sustain**, **1m ramp-down** (~14m total).

Same HTTP abort thresholds as read perf: **8s** timeout; fail rate ≥**2%**; global p95 ≥**8s**; feed / feed_page / dashboard_rpc p95 ≥**5s**.

### Extra metrics

| Metric | Meaning |
|--------|---------|
| `tradetraxs_ws_connect_ok` / `_fail` | WebSocket connect outcomes |
| `tradetraxs_ws_subscribe_ok` / `_fail` | `phx_join` ok vs error reply |
| `tradetraxs_dm_send_ok` / `_fail` | DM inserts |
| `tradetraxs_room_send_ok` / `_fail` | Room inserts |
| `tradetraxs_realtime_delivery_ms` | HTTP send → `postgres_changes` on open WS (best effort) |
| `tradetraxs_realtime_delivery_miss` | No matching event before session end |
| `tradetraxs_messaging_bootstrap_ms` | Inbox RPC latency |
| `tradetraxs_dm_thread_bootstrap_ms` | Thread RPC latency |

Tagged HTTP pages: `messaging_bootstrap`, `dm_thread_bootstrap`, `dm_send`, `room_send`, `realtime_*`.

End-of-run **stdout** includes numeric Realtime/messaging counters and trends (not just metric names). A JSON snapshot is written to `loadtest/out/realistic300-full-last-summary.json` (gitignored).

## Prerequisites

1. Successful prod **smoke** and operator comfort with **`realistic300`** read-only run recommended first.
2. **50** perf users in `LOADTEST_USERS_JSON` (same pool as `onefifty`).
3. **Isolation fixture provisioned** — `python3 loadtest/scripts/provision-realistic300-full-fixture.py` (see **`loadtest/docs/REALISTIC300_FULL_FIXTURE_PROVISION_STEPS.md`**).
4. Set `LOADTEST_REALISTIC300_FULL_FIXTURE_FILE=loadtest/fixtures/realistic300-full-isolation.json` (or inline `LOADTEST_REALISTIC300_FULL_FIXTURE_JSON`).

## Environment

```bash
LOADTEST_ENV=production
TRADETRAXS_PROD_PERF_CONFIRM=yes
TRADETRAXS_PRODUCTION_PROJECT_REF=fobudrkniacatvilbofw

TRADETRAXS_PROD_PERF_REALISTIC300_FULL=yes
LOADTEST_MAX_VUS=300

LOADTEST_FEED_SCOPE=following
LOADTEST_VU_START_JITTER_SEC=45

LOADTEST_FULL_SKIP_PUSH=yes
LOADTEST_FULL_MAX_DM_SENDS_TOTAL=200
LOADTEST_FULL_MAX_ROOM_SENDS_TOTAL=200
# Optional per-VU ceiling (must not exceed partition allowance):
# LOADTEST_FULL_MAX_DM_SENDS_PER_VU=3
# LOADTEST_FULL_MAX_ROOM_SENDS_PER_VU=2

LOADTEST_SUPABASE_URL=https://fobudrkniacatvilbofw.supabase.co
LOADTEST_SUPABASE_ANON_KEY=...
LOADTEST_WEB_URL=https://app.tradetraxs.com
LOADTEST_USERS_JSON='[ ... 50 perf accounts ... ]'

# Minified JSON on one line, or use a file path pattern your shell supports
LOADTEST_REALISTIC300_FULL_FIXTURE_JSON='{"schemaVersion":1,...}'
```

## Run (manual)

```bash
chmod +x loadtest/scripts/verify-realistic300-full-env.sh
./loadtest/scripts/verify-realistic300-full-env.sh --config-only

set -a && source loadtest/.env.production-perf && set +a
k6 run loadtest/prod-realistic300-full.js
```

Use `--config-only` (or `LOADTEST_VERIFY_CONFIG_ONLY=yes`) so verification does **not** password-grant all 50 users before k6 `setup()` (reduces Supabase Auth 429 risk).

## Cleanup (manual, after run)

```bash
set -a && source loadtest/.env.production-perf && set +a
node loadtest/scripts/cleanup-realistic300-full-data.mjs --dry-run
node loadtest/scripts/cleanup-realistic300-full-data.mjs
```

Optional one-shot purge with local service role (never commit; still **fixture ID + tag** only):

`TRADETRAXS_LOADTEST_SERVICE_ROLE_CONFIRM=yes TRADETRAXS_LOADTEST_SERVICE_ROLE_KEY=... node loadtest/scripts/cleanup-realistic300-full-data.mjs`

## Interpreting results

- Compare **`tradetraxs_realtime_delivery_ms` p95** to HTTP p95 — large gap may indicate Realtime/ replication lag under load.
- **`tradetraxs_realtime_delivery_miss`** — joins without matching events (may be normal if no send in that iteration).
- **Write failures** — check rate limits (`message_send`, `room_message`, free-plan **25 DM/24h** if perf users are not Pro).
- Do not treat this run as a substitute for **`realistic300`** (read-only) or **`onefifty`** stress.
