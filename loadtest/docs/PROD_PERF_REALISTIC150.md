# Realistic150 — 150 concurrent iOS-shaped read load

Contrasts with **`onefifty`**: same 150 virtual users, but **not** the aggressive constant-VU stress mix. This mode simulates natural iOS usage with screen cache TTLs, idle time, and a gradual ramp.

For **300 VUs** with the same mix and behavior, use **`realistic300`** — see `loadtest/docs/PROD_PERF_REALISTIC300.md`.

## Sessions vs accounts

| | realistic150 | onefifty (unchanged) |
|--|----------------|----------------------|
| Concurrent VUs | **150** | **150** |
| Authenticated accounts | **50** (required) | **50** (required) |
| VU → user mapping | Pseudo-random stable map (~3 VUs per account on average) | Round-robin `(vuId - 1) % 50` |
| Executor | `ramping-vus` (3m → 150, 10m sustain, 1m ramp-down) | `constant-vus` 60s |
| Workload | `realistic150_ios` (forced) | `client_realistic` (typical) |

**150 concurrent virtual sessions ≠ 150 unique users.** Multiple VUs share the same JWT/account; this matches many devices or reinstalls on shared perf accounts, not 150 distinct humans.

## Activity mix (each iteration)

| Weight | Behavior |
|--------|----------|
| 25% | **Feed** — following scope; ~20% paginate; cache TTL ~90–180s; ~7% pull-to-refresh |
| 15% | **Dashboard** — profile + accounts + owner trade rows (+ optional dashboard RPC) |
| 15% | **Profile + trades** — public profile, follower counts, public trades list |
| 10% | **Calendar** — accounts + calendar bootstrap RPC |
| 15% | **Passive view** — read/watch already-loaded feed/profile **without HTTP** |
| 20% | **Idle / backgrounded** — 60–180s sleep, no API calls |

Think time after active fetches: **~10–60s**. Occasional short pauses between iterations.

## Native cache simulation

Per-VU in-memory TTL per screen. If the user “returns” to a screen before TTL expires, **no PostgREST call** (unless pull-to-refresh roll succeeds). This approximates iOS `FeedSessionStore` / in-tab cache — k6 still never hits real on-device storage.

## Included API surface (read-only)

Same contracts as `loadtest/lib/read-workload-prod.js`:

- Session profile, accounts
- `rpc_v1_trades_owner_rows`, `rpc_v1_feed_bootstrap`, `rpc_v1_dashboard_bootstrap`, `rpc_v1_calendar_bootstrap`
- Profile REST reads (public profile, follower head counts, public trades)

## Explicitly excluded

- **Writes** (posts, trades, likes, follows, uploads)
- **Messaging** / notifications bootstrap
- **Supabase Realtime** (websockets)
- **Media downloads** (video/thumbnail/CDN; no clip bytes fetched)
- **Leaderboard**, billing, broker, imports
- **Next.js SSR** routes (direct PostgREST only, same as other prod perf modes)

## Prerequisites

- Successful **smoke** (and recommended progression through lower brackets per `PRODUCTION_READ_PERF.md`)
- **Exactly 50** entries in `LOADTEST_USERS_JSON` (same pool as `onefifty` — see `PROD_PERF_ONEFIFTY_FIFTY_USERS.md`)
- Do **not** run `preflight-prod-perf-auth.sh` immediately before k6 if you already verified 50 grants (Auth rate limits)

## Environment (`loadtest/.env.production-perf`)

```bash
LOADTEST_ENV=production
TRADETRAXS_PROD_PERF_CONFIRM=yes
TRADETRAXS_PRODUCTION_PROJECT_REF=fobudrkniacatvilbofw

LOADTEST_PROD_PERF_MODE=realistic150
LOADTEST_MAX_VUS=150
TRADETRAXS_PROD_PERF_REALISTIC150=yes

LOADTEST_WORKLOAD_KIND=realistic150_ios
LOADTEST_FEED_SCOPE=following
LOADTEST_VU_START_JITTER_SEC=45

LOADTEST_SUPABASE_URL=...
LOADTEST_SUPABASE_ANON_KEY=...
LOADTEST_WEB_URL=https://app.tradetraxs.com
LOADTEST_USERS_JSON='[ ... 50 perf accounts ... ]'
```

`LOADTEST_WORKLOAD_KIND` is overridden to `realistic150_ios` when mode is `realistic150`.

## Run (operator — manual)

```bash
./loadtest/scripts/verify-production-perf-env.sh
set -a && source loadtest/.env.production-perf && set +a
k6 run loadtest/prod-read-perf.js
```

Monitor Supabase (CPU, connections, API errors) and Vercel during the **~14 minute** window (3m ramp + 10m sustain + 1m ramp-down + graceful stop).

## Interpreting results

Same thresholds as other prod perf modes (8s HTTP timeout; abort if failed rate ≥2%, global p95 ≥8s, feed/feed_page/dashboard_rpc p95 ≥5s).

| Signal | Meaning |
|--------|---------|
| **`http_req_duration{page:feed}` p95** | Following feed RPC under **distributed** load (not all VUs on Feed at once) |
| **`http_req_failed` / HTTP 0** | Timeouts or 5xx; compare to `onefifty` stress run |
| **Lower RPS than onefifty** | Expected — idle, passive, and cache-skip iterations produce fewer HTTP calls |
| **Endpoint breakdown** | Should show mix across dashboard, calendar, profile, trades — not feed-only |
| **Abort on threshold** | Treat as stop signal; check Postgres `pg_stat_statements` / sampler runbook if feed-bound |

Compare **realistic150** (capacity under natural mix) vs **onefifty** (worst-case synchronized client_realistic stress) — do not treat one as a substitute for the other.
