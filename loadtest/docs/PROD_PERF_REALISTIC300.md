# Realistic300 — 300 concurrent iOS-shaped read load

Same workload implementation as **`realistic150`** (`realistic150_ios` in `loadtest/lib/read-workload-realistic150.js`): activity mix, per-VU screen TTL cache, think times, idle/passive periods, and read-only endpoints are **unchanged**. Only concurrency, ramp target, and confirm env differ.

**`onefifty`** and **`realistic150`** are unchanged by this mode.

## Sessions vs accounts

| | realistic300 | realistic150 |
|--|----------------|----------------|
| Concurrent VUs | **300** | **150** |
| Authenticated accounts | **50** (required) | **50** (required) |
| VU → user mapping | Pseudo-random stable map (~**6** VUs per account on average) | ~**3** VUs per account on average |
| Executor | `ramping-vus` (3m → 300, 10m sustain, 1m ramp-down) | 3m → 150, same sustain/ramp-down |
| Workload | `realistic150_ios` (forced) | `realistic150_ios` (forced) |

**300 concurrent virtual sessions ≠ 300 unique users.** Multiple VUs share the same JWT/account.

Activity mix, cache behavior, included APIs, and exclusions are documented in **`loadtest/docs/PROD_PERF_REALISTIC150.md`** (same for both modes).

## Environment (`loadtest/.env.production-perf`)

```bash
LOADTEST_ENV=production
TRADETRAXS_PROD_PERF_CONFIRM=yes
TRADETRAXS_PRODUCTION_PROJECT_REF=fobudrkniacatvilbofw

LOADTEST_PROD_PERF_MODE=realistic300
LOADTEST_MAX_VUS=300
TRADETRAXS_PROD_PERF_REALISTIC300=yes

LOADTEST_WORKLOAD_KIND=realistic150_ios
LOADTEST_FEED_SCOPE=following
LOADTEST_VU_START_JITTER_SEC=45

LOADTEST_SUPABASE_URL=...
LOADTEST_SUPABASE_ANON_KEY=...
LOADTEST_WEB_URL=https://app.tradetraxs.com
LOADTEST_USERS_JSON='[ ... 50 perf accounts ... ]'
```

`LOADTEST_WORKLOAD_KIND` is overridden to `realistic150_ios` when mode is `realistic300`.

## Run (operator — manual)

```bash
./loadtest/scripts/verify-production-perf-env.sh
set -a && source loadtest/.env.production-perf && set +a
k6 run loadtest/prod-read-perf.js
```

Monitor Supabase (CPU, connections, API errors) and Vercel during the **~14 minute** window (3m ramp + 10m sustain + 1m ramp-down + graceful stop).

## Interpreting results

Same thresholds as other prod perf modes: **8s** HTTP timeout; abort if failed rate ≥**2%**, global p95 ≥**8s**, feed / feed_page / dashboard_rpc p95 ≥**5s**.

| Signal | Meaning |
|--------|---------|
| **Summary line** | Reports up to **300** concurrent VUs on **50** authenticated accounts |
| **RPS vs realistic150** | Higher peak in-flight load at 300 VUs; per-VU behavior identical so compare p95/failures, not raw RPS alone |
| **vs onefifty** | Realistic300 = natural mix + cache skips; onefifty = 60s synchronized `client_realistic` stress |

Compare **realistic300** to **realistic150** for scaling headroom under the same iOS-shaped mix; compare either to **onefifty** for worst-case stress — not as substitutes.
