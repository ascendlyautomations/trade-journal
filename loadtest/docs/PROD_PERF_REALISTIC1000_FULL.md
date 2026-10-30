# Realistic1000_full — overload probe (reads + messaging + Realtime)

**Separate script:** `loadtest/prod-realistic1000-full.js` — does **not** change `prod-realistic600-full.js` (600 VU) or `prod-realistic300-full.js` (300 VU / 50 accounts).

Same **85% / 15%** workload at **1000 VUs** on the **same 100 perf accounts** as realistic600_full (**10 VUs per account**, even split) and the **same isolation fixture** (`realistic600-full-isolation.json` or a copy referenced via `LOADTEST_REALISTIC1000_FULL_FIXTURE_*`).

| Phase | Duration | VUs |
|-------|----------|-----|
| Ramp up | **5m** | 0 → **1000** |
| Sustain | **10m** | **1000** |
| Ramp down | **2m** | 1000 → 0 |
| Graceful ramp-down | **2m** | (executor) |

| | 600_full | 1000_full |
|---|----------|-----------|
| Script | `prod-realistic600-full.js` | `prod-realistic1000-full.js` |
| VUs | 600 | 1000 |
| VUs / account | 6 | 10 |
| Accounts | `LOADTEST_REALISTIC600_USERS_JSON` (100) | same |
| Fixture | `LOADTEST_REALISTIC600_FULL_FIXTURE_*` | same fixture (600 or 1000 env keys) |
| Message tag | `[loadtest:realistic600_full]` | `[loadtest:realistic1000_full]` |
| Global DM/room caps | 400 / 400 | **700 / 700** (1400 combined; partitioned across 1000 VUs) |
| Summary JSON | `loadtest/out/realistic600-full-last-summary.json` | `loadtest/out/realistic1000-full-last-summary.json` |

Fixture provisioning: **`loadtest/docs/REALISTIC600_FULL_FIXTURE_PROVISION_STEPS.md`** (no new prod users required for 1000).

## Environment (1000 run)

Unset `TRADETRAXS_PROD_PERF_REALISTIC600_FULL` before a 1000 run (only one gate at a time).

```bash
TRADETRAXS_PROD_PERF_REALISTIC1000_FULL=yes
LOADTEST_MAX_VUS=1000
LOADTEST_FULL_MAX_DM_SENDS_TOTAL=700
LOADTEST_FULL_MAX_ROOM_SENDS_TOTAL=700
LOADTEST_FULL_MESSAGE_TAG=[loadtest:realistic1000_full]
LOADTEST_REALISTIC600_USERS_JSON='[ ... 100 accounts ... ]'
LOADTEST_REALISTIC600_FULL_FIXTURE_FILE=loadtest/fixtures/realistic600-full-isolation.json
LOADTEST_K6_SETUP_AUTH_SPACING_SEC=3
LOADTEST_FULL_SKIP_PUSH=yes
LOADTEST_FULL_REALTIME_DELIVERY_TIMEOUT_MS=8000
```

## Verify and run

```bash
set -a && source loadtest/.env.production-perf && set +a
./loadtest/scripts/verify-realistic1000-full-env.sh --config-only
./loadtest/scripts/run-realistic1000-full.sh
```

Manual:

```bash
mkdir -p loadtest/out
export LOADTEST_REALISTIC600_FULL_FIXTURE_JSON="$(cat loadtest/fixtures/realistic600-full-isolation.json)"
k6 run loadtest/prod-realistic1000-full.js
```

Report: `loadtest/out/realistic1000-full-last-summary.json` (`sendCapUtilization`, `messagingAndRealtime`, activity mix, HTTP).

**Send caps:** 700 DM + 700 room (1400 combined). Partitioning gives **700 VUs one send each** and **300 VUs zero** per channel. Summary reports **allowance unused** (configured − consumed) separately from **blocked attempts** (rolled send with no allowance left).

## Cleanup (tag-scoped)

```bash
export LOADTEST_FULL_MESSAGE_TAG='[loadtest:realistic1000_full]'
export LOADTEST_REALISTIC600_FULL_FIXTURE_FILE=loadtest/fixtures/realistic600-full-isolation.json
node loadtest/scripts/cleanup-realistic300-full-data.mjs --dry-run --realistic1000
node loadtest/scripts/cleanup-realistic300-full-data.mjs --realistic1000
```

Only rows matching **`[loadtest:realistic1000_full]`** inside fixture-scoped conversations/rooms are touched.

## Client resource notes (Mac mini)

k6 has no hard 600-VU ceiling; **1000 VUs** is supported if the runner machine has enough CPU, RAM, and file descriptors.

- Check **`ulimit -n`** before a long run; **≥ 10240** is recommended (many concurrent HTTP + WebSocket connections during the 15% messaging/Realtime slice). Example: `ulimit -n 65536` in the shell before `run-realistic1000-full.sh`.
- Peak WebSocket count is bounded by active messaging iterations, not all 1000 VUs at once, but sustained load still opens many sockets.
- Use a recent k6 (`k6 version`); verify script prints version and warns on low `ulimit`.
- If the Mac mini hits client limits first, metrics will show elevated client-side errors/timeouts unrelated to Supabase — compare with server-side logs.

Auth setup: **100 password grants in setup only**, default **3s** spacing, **12m** `setupTimeout`, Retry-After + exponential backoff (same as 600_full).
