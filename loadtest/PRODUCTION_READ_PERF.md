# Production read-only performance test

**Staging clone work is paused.** This is a controlled probe against **live production** — not staging.

## Safety model

| Control | Detail |
|---------|--------|
| Script | `loadtest/prod-read-perf.js` only |
| Workload | `LOADTEST_WORKLOAD_KIND=supabase_direct` (default) or `client_realistic` — see `loadtest/WORKLOAD_TAXONOMY.md` |
| Env gate | `LOADTEST_ENV=production` **and** `TRADETRAXS_PROD_PERF_CONFIRM=yes` |
| Smoke (first) | **1 VU × 30s** — `LOADTEST_PROD_PERF_MODE=smoke`, `LOADTEST_MAX_VUS=1` |
| Full (after smoke) | **5 VU × 60s** — `LOADTEST_PROD_PERF_MODE=full`, `LOADTEST_MAX_VUS=5`, **`TRADETRAXS_PROD_PERF_FULL=yes`** |
| Ten (after smoke) | **10 VU × 60s** — `LOADTEST_PROD_PERF_MODE=ten`, `LOADTEST_MAX_VUS=10`, **`TRADETRAXS_PROD_PERF_TEN=yes`** |
| Twentyfive (after smoke + ten) | **25 VU × 60s** — `LOADTEST_PROD_PERF_MODE=twentyfive`, `LOADTEST_MAX_VUS=25`, **`TRADETRAXS_PROD_PERF_TWENTYFIVE=yes`**; supports `LOADTEST_WORKLOAD_KIND=client_realistic` |
| Fifty (after smoke + ten) | **50 VU × 60s** — `LOADTEST_PROD_PERF_MODE=fifty`, `LOADTEST_MAX_VUS=50`, **`TRADETRAXS_PROD_PERF_FIFTY=yes`**; same realistic workload options as twentyfive |
| Seventyfive (after fifty) | **75 VU × 60s** — `LOADTEST_PROD_PERF_MODE=seventyfive`, `LOADTEST_MAX_VUS=75`, **`TRADETRAXS_PROD_PERF_SEVENTYFIVE=yes`**; **≥30** test users |
| Hundred (after seventyfive) | **100 VU × 60s** — `LOADTEST_PROD_PERF_MODE=hundred`, `LOADTEST_MAX_VUS=100`, **`TRADETRAXS_PROD_PERF_HUNDRED=yes`** |
| Onefifty (after hundred) | **150 VU × 60s** — `LOADTEST_PROD_PERF_MODE=onefifty`, `LOADTEST_MAX_VUS=150`, **`TRADETRAXS_PROD_PERF_ONEFIFTY=yes`**; **exactly 50** dedicated users |
| Realistic150 (optional) | **Ramp → 150 VU, 10m sustain** — `LOADTEST_PROD_PERF_MODE=realistic150`, **`TRADETRAXS_PROD_PERF_REALISTIC150=yes`**; **50 accounts**, **150 concurrent sessions**; iOS mix — see `loadtest/docs/PROD_PERF_REALISTIC150.md` |
| Realistic300 (optional) | **Ramp → 300 VU, 10m sustain** — `LOADTEST_PROD_PERF_MODE=realistic300`, **`TRADETRAXS_PROD_PERF_REALISTIC300=yes`**; **50 accounts**, **300 concurrent sessions**; same iOS mix as realistic150 — see `loadtest/docs/PROD_PERF_REALISTIC300.md` |
| Realistic300_full (optional) | **Separate script** `loadtest/prod-realistic300-full.js` — reads + isolated DM/room writes + Realtime; **`TRADETRAXS_PROD_PERF_REALISTIC300_FULL=yes`** — see `loadtest/docs/PROD_PERF_REALISTIC300_FULL.md` |
| Realistic600_full (optional) | **Separate script** `loadtest/prod-realistic600-full.js` — same full workload at **600 VUs** (informational thresholds); **`TRADETRAXS_PROD_PERF_REALISTIC600_FULL=yes`** — see `loadtest/docs/PROD_PERF_REALISTIC600_FULL.md` |
| Executor | `constant-vus` (most modes); **`ramping-vus`** for realistic150 and realistic300 |
| Staging | **Blocked** (`hxlcvffvyadlxcsqxxoy`, staging URLs) |
| Credentials | Production **anon** key + **dedicated test user(s)** only (no service role) |
| Reads only | Dashboard, Feed, Profile, Trades, Calendar paths |
| Excluded | Messages bootstrap, leaderboard, writes, imports, broker, billing |
| Timeouts | 8s per HTTP call |
| Pacing | 4–8s between page groups per VU |
| Auto-stop | k6 `abortOnFail`: failed rate ≥2%; **global** `http_req_duration` p95 ≥8s; **feed**, **feed_page**, and **dashboard_rpc** tagged p95 ≥5s |
| Emergency stop | **Ctrl+C once** — graceful wind-down; **Ctrl+C twice** — hard abort; watch Supabase/Vercel live |

`loadtest/phase-a-read.js` remains **staging-only** (`LOADTEST_ENV=staging`).

## Audit: `phase-a-read.js` vs production

| Item | Staging script | Production script |
|------|----------------|-------------------|
| Production URLs | **Refused** | Required (allowlisted hosts + ref) |
| Ramp 1→10→… | Yes | **No** |
| Messages RPC | Included | **Removed** (avoid notification side paths) |
| Leaderboard API | Included | **Removed** (out of scope) |
| Calendar | Implicit via trades | **Explicit** calendar_trades + accounts |
| Dashboard trades | REST journal/analytics (removed) | `rpc_v1_trades_owner_rows` + optional `rpc_v1_dashboard_bootstrap` |
| Calendar | REST analytics trades (removed) | `rpc_v1_calendar_bootstrap` (month/year, auth-scoped) |

Auth password grant runs once per VU session (session token only; **no sign-up**).

## Preflight (runs automatically at k6 `setup()`)

`setup()` performs **one password grant per entry** in `LOADTEST_USERS_JSON` (30 grants for hundred), stores tokens in setup data, and runs RPC preflight with the first account. VUs reuse those tokens (round-robin by `vu.idInTest`); throttled refresh only on **401**, avoiding Auth **429** storms at stage start.

Before VUs load, one pass verifies:

- Production auth (password grant) for the test user
- Read-only GETs: profile, accounts (scoped to viewer)
- Read RPCs: `rpc_v1_trades_owner_rows`, `rpc_v1_feed_bootstrap`, `rpc_v1_dashboard_bootstrap`, `rpc_v1_calendar_bootstrap`
- Shared definitions: `loadtest/lib/read-workload-prod.js` (preflight = VU contracts)
- Response shape checks (profile id matches session user; arrays parse)
- Pacing constants **4–8s** between page groups (enforced in default loop)

No response bodies or credentials are printed to stdout.

## Setup (do not commit secrets)

```bash
cp loadtest/.env.production-perf.example loadtest/.env.production-perf
chmod 600 loadtest/.env.production-perf
# Edit: production Supabase URL, anon key, app URL, 1–10 test users JSON (ten mode)
```

Use a **dedicated** production test account whose data you are allowed to load-test (prefer minimal follower graph).

## Monitoring (manual during the 60s run)

Open before starting k6:

1. **Supabase** → production project → Database (CPU, connections), Logs (API errors), Reports  
2. **Vercel** → production deployment → Runtime logs / Observability (5xx, latency)

**150-VU timeout evidence:** use the step-by-step runbook  
[`loadtest/diagnostics/onefifty-vu-timeout-runbook.md`](diagnostics/onefifty-vu-timeout-runbook.md)  
(lightweight SQL sampling + Dashboard interpretation; read-only).

**Stop early** (Ctrl+C k6) if you see error spikes, connection exhaustion, or user-visible degradation.

## Run smoke first (operator only)

```bash
set -a && source loadtest/.env.production-perf && set +a
k6 run loadtest/prod-read-perf.js
```

Env file must have `LOADTEST_PROD_PERF_MODE=smoke`, `LOADTEST_MAX_VUS=1`, and `TRADETRAXS_PROD_PERF_CONFIRM=yes`.

## Run full (only after smoke passes)

Edit `loadtest/.env.production-perf`: `LOADTEST_PROD_PERF_MODE=full`, `LOADTEST_MAX_VUS=5`, add `TRADETRAXS_PROD_PERF_FULL=yes`, then the same `k6 run` command.

## Run ten (10 VU × 60s, only after smoke passes)

Edit `loadtest/.env.production-perf`:

- `LOADTEST_PROD_PERF_MODE=ten`
- `LOADTEST_MAX_VUS=10`
- `TRADETRAXS_PROD_PERF_TEN=yes`
- `LOADTEST_USERS_JSON` — **1–10** dedicated production test users (VUs round-robin if fewer than 10)

Verify, then run:

```bash
./loadtest/scripts/verify-production-perf-env.sh
set -a && source loadtest/.env.production-perf && set +a
k6 run loadtest/prod-read-perf.js
```

## Run twentyfive (25 VU × 60s, only after smoke and ten pass)

Edit `loadtest/.env.production-perf`:

- `LOADTEST_PROD_PERF_MODE=twentyfive`
- `LOADTEST_MAX_VUS=25`
- `TRADETRAXS_PROD_PERF_TWENTYFIVE=yes`
- `LOADTEST_USERS_JSON` — **1–25** dedicated production test users (for `client_realistic`, prefer **≥5** users)
- Optional: `LOADTEST_WORKLOAD_KIND=client_realistic` (VU startup jitter and mixed Dashboard/Feed/Trades/Calendar/Profile)

Same verify + `k6 run` as ten mode. Uses **10s gracefulStop**, existing thresholds, and scenario-start jitter (default 12s for `client_realistic`, 0 for `supabase_direct` unless `LOADTEST_VU_START_JITTER_SEC` is set).

## Run fifty (50 VU × 60s, only after smoke and ten pass)

Edit `loadtest/.env.production-perf`:

- `LOADTEST_PROD_PERF_MODE=fifty`
- `LOADTEST_MAX_VUS=50`
- `TRADETRAXS_PROD_PERF_FIFTY=yes`
- `LOADTEST_USERS_JSON` — **1–50** dedicated production test users (for `client_realistic`, **≥5** required; **15 accounts** recommended for fifty → ~3 VUs each, varied follows)
- Optional: `LOADTEST_WORKLOAD_KIND=client_realistic`, `LOADTEST_FEED_SCOPE=following`, `LOADTEST_VU_START_JITTER_SEC=12`

Same verify + `k6 run` as twentyfive (constant 50 VUs for 60s, **10s gracefulStop**, same thresholds and 8s request timeout).

## Run seventyfive (75 VU × 60s, bracket between fifty and hundred)

Edit `loadtest/.env.production-perf`:

- `LOADTEST_PROD_PERF_MODE=seventyfive`
- `LOADTEST_MAX_VUS=75`
- `TRADETRAXS_PROD_PERF_SEVENTYFIVE=yes`
- `LOADTEST_USERS_JSON` — **≥30** dedicated users (same pool as fifty/hundred)
- `LOADTEST_WORKLOAD_KIND=client_realistic`, `LOADTEST_FEED_SCOPE=following`, `LOADTEST_VU_START_JITTER_SEC=12`

```bash
./loadtest/scripts/verify-production-perf-env.sh
# Optional (separate from k6 — avoid back-to-back with setup auth):
# ./loadtest/scripts/preflight-prod-perf-auth.sh
set -a && source loadtest/.env.production-perf && set +a
k6 run loadtest/prod-read-perf.js
```

Do **not** chain `preflight-prod-perf-auth.sh` immediately before `k6 run` (duplicates password grants and can Auth **429**). k6 `setup()` already authenticates all users once.

For **onefifty**, `verify-production-perf-env.sh` runs preflight for all **50** accounts; wait **≥2 minutes** before `k6 run`, or skip verify’s embedded preflight and run verify with env checks only if you hit setup auth failures around user index **25–30** (~26s into setup). Setup errors now include **HTTP status** and sanitized Auth `error_code` / `msg` (email masked).

Summary output includes **run timing**: setup wall time vs approximate scenario execution (HTTP metrics exclude setup).

## Run hundred (100 VU × 60s, only after seventyfive)

Edit `loadtest/.env.production-perf`:

- `LOADTEST_PROD_PERF_MODE=hundred`
- `LOADTEST_MAX_VUS=100`
- `TRADETRAXS_PROD_PERF_HUNDRED=yes`
- `LOADTEST_USERS_JSON` — **≥30** dedicated users required (verify script enforces); **30 accounts** recommended → ~3 VUs each
- `LOADTEST_WORKLOAD_KIND=client_realistic`, `LOADTEST_FEED_SCOPE=following`, `LOADTEST_VU_START_JITTER_SEC=12`

Use the same **verify → k6** flow as seventyfive (optional preflight only when not run back-to-back with k6).

## Run onefifty (150 VU × 60s, only after hundred)

Edit `loadtest/.env.production-perf`:

- `LOADTEST_PROD_PERF_MODE=onefifty`
- `LOADTEST_MAX_VUS=150`
- `TRADETRAXS_PROD_PERF_ONEFIFTY=yes`
- `LOADTEST_USERS_JSON` — **exactly 50** dedicated users (verify enforces; see `loadtest/docs/PROD_PERF_ONEFIFTY_FIFTY_USERS.md`)
- `LOADTEST_WORKLOAD_KIND=client_realistic`, `LOADTEST_FEED_SCOPE=following`, `LOADTEST_VU_START_JITTER_SEC=12`

```bash
./loadtest/scripts/verify-production-perf-env.sh
# verify runs password-grant preflight for all 50 accounts; do not repeat immediately before k6
set -a && source loadtest/.env.production-perf && set +a
k6 run loadtest/prod-read-perf.js
```

Round-robin unchanged: VU *n* → user `(n - 1) % 50` (~3 VUs per account at 150 VUs).

## Run realistic150 (150 VU iOS-shaped mix — separate from onefifty stress)

Does **not** replace or modify **onefifty**. Use when you want natural activity mix, screen-cache skips, and gradual ramp instead of 60s constant aggressive `client_realistic`.

Full doc: **`loadtest/docs/PROD_PERF_REALISTIC150.md`**

```bash
./loadtest/scripts/verify-production-perf-env.sh
set -a && source loadtest/.env.production-perf && set +a
k6 run loadtest/prod-read-perf.js
```

Env highlights: `LOADTEST_PROD_PERF_MODE=realistic150`, `TRADETRAXS_PROD_PERF_REALISTIC150=yes`, `LOADTEST_WORKLOAD_KIND=realistic150_ios`, exactly **50** users, `LOADTEST_VU_START_JITTER_SEC=45`.

## Run realistic300 (300 VU iOS-shaped mix — same behavior as realistic150)

Same activity mix, screen TTL cache, think times, and exclusions as **realistic150**; only concurrency and confirm gate differ. **300 concurrent VUs share 50 authenticated accounts** (~6 sessions per account on average).

Full doc: **`loadtest/docs/PROD_PERF_REALISTIC300.md`**

```bash
./loadtest/scripts/verify-production-perf-env.sh
set -a && source loadtest/.env.production-perf && set +a
k6 run loadtest/prod-read-perf.js
```

Env highlights: `LOADTEST_PROD_PERF_MODE=realistic300`, `TRADETRAXS_PROD_PERF_REALISTIC300=yes`, `LOADTEST_MAX_VUS=300`, `LOADTEST_WORKLOAD_KIND=realistic150_ios`, exactly **50** users, `LOADTEST_VU_START_JITTER_SEC=45`.

## Twentyfive + client_realistic failure pattern (~48s abort)

Observed with **1 shared test account**, **following** Feed, **12s** VU jitter:

- **2.93%** HTTP failures (trips **2%** `abortOnFail`) — failures are **k6 HTTP 0** (`request timeout` at **8s**), not PostgREST 4xx/5xx bodies.
- **Correlated burst at t≈45–47s**: `rpc_v1_feed_bootstrap`, `rpc_v1_dashboard_bootstrap`, `profiles` GET, `rpc_v1_trades_owner_rows` time out in the **same second** → **shared Supabase/API or pool queue**, not Feed-only SQL.
- **Bimodal latency**: global p95 ~1.4s while Feed p95 **8001ms** (= timeout ceiling in the Feed sample); Dashboard RPC / Feed page p95 ~5s = heavy tail before timeouts.
- **Jitter** spreads the **initial** start; after ~30–40s of full 25-VU load, iterations **phase-lock** (similar pacing), increasing concurrent in-flight requests.
- **No client cache**: k6 bypasses web/iOS first-page cache/single-flight → **25× identical** `auth.uid()` work when one account is used.

**Supabase evidence to collect on the next allowed run** (time window **t=40–50s** UTC):

| Source | What to check |
|--------|----------------|
| **Database → Reports** | Active connections vs max, CPU %, memory |
| **Logs → API** | 5xx/504 rate; latency spikes on `/rest/v1/rpc/*` and `/rest/v1/profiles` |
| **Logs → Postgres** | `too many connections`, pool/client errors, queries running >5s (`loadtest/diagnostics/production-feed-readonly.sql` §1–2) |
| **Project → Database → Pooler** | Pool mode/size; queueing under load |

**Smallest evidence-backed fix (methodology):** `twentyfive` + `client_realistic` requires **≥5 dedicated users** in `LOADTEST_USERS_JSON` (verify script enforces). Prefer **1 user per VU** for interpretable capacity numbers. Do not treat single-account twentyfive as representative of 25 real users.

## Feed timeouts at 25 VUs (diagnosis)

Evidence from a non-overlapping hundred run (~12s into 25-VU stage):

| Signal | Interpretation |
|--------|----------------|
| `page:feed` p95 **8001ms**, p99 **8001ms**, n=23 | Matches k6 **`REQUEST_TIMEOUT` (8s)** — failures are **client-side timeouts** (HTTP 0), not PostgREST 200s at ~8s |
| `page:feed_page` p95 **~1.3s** | Same RPC, **cursor set** — cheaper keyset branch |
| `page:dashboard_rpc` p95 **~199ms** | Other RPCs healthy in the same window |
| Profile REST timeout same second as feed | **Shared** Supabase/API path contention, not feed-only SQL |
| 1.83% HTTP failures | Just under 2% global abort; **feed 5s p95** aborted first |

**Workload:** k6 calls PostgREST **directly** (no Next.js `feedBootstrapCache` / single-flight). With **one test user**, up to **25 identical** `global` / first-page bootstraps can run in parallel at stage start — duplicate DB work.

**SQL (repo):** `rpc_v1_feed_bootstrap` unions four content branches (limit 9 each), `users_have_active_block` per row, merge sort, hydration + `feed_engagement_counts`. First page scans **recent** rows; cursor page uses `_v1_feed_before_cursor` (narrower). See `loadtest/diagnostics/production-feed-readonly.sql` for read-only checks and **EXPLAIN without ANALYZE** templates.

**Next run:** summary includes **feed_cursor:first|next** latency tags and **`tradetraxs_http_outcome`** (timeout vs ok). Use multiple test users in `LOADTEST_USERS_JSON` to reduce identical-cache-miss storms (still read-only).

## Feed threshold vs global latency (hundred abort ~70s)

k6 evaluates **tagged** thresholds on **only** requests carrying that tag. Overall p95 can stay low (e.g. ~1.3s) while **`http_req_duration{page:feed}`** p95 exceeds **5s** if feed RPCs are the tail-heavy subset.

Observed abort pattern (0% HTTP failures, stop at ~70s):

- **`hundred_10vu`** had finished its 60s window but was still in **graceful wind-down** while **`hundred_25vu`** had just started → **~35 concurrent VUs**, not 25.
- Abort metric was **`page:feed`** only (stricter **5s** p95 vs **8s** global).
- Route **3** runs **two** feed RPCs when pagination applies (`feed` + `feed_page`); only the first page is tagged `page:feed` for the threshold, but both add load during overlap.

Production feed reads use the same **`rpc_v1_feed_bootstrap`** path as the app (`FEED_PAGE_LIMIT=8`), with migrations **`20260820224542_rpc_v1_feed_bootstrap_optimize.sql`** (keyset cursor, indexes) and **`20261005140000_feed_bootstrap_safe_trade_reads.sql`** (definer trade payload for privacy). No production DB change was made in this investigation.

**Fixes in repo (no prod re-run):** non-overlapping hundred stages, brief pause between feed page-1 and page-2 in the load script, richer summary output. Re-run hundred only after reviewing overlap fix; compare new **endpoint latency** lines to global percentiles.

## Report template (fill after run)

- k6 stdout: req/s, failed %, p50, p95, p99, iterations (overall + per-stage for hundred); **tagged endpoint latency** and **thresholds crossed**  
- Supabase: peak CPU, peak connections, error count  
- Vercel: 5xx count, slow routes  
- Decision: proceed / hold / revert env changes  
