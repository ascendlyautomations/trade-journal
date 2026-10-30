# Load-test workload taxonomy

## Real client Feed paths (audit)

| Layer | Web | iOS |
|-------|-----|-----|
| Transport | Browser **Supabase JS** → PostgREST `/rest/v1/rpc/rpc_v1_feed_bootstrap` | **BackendV2RPCClient** → same PostgREST RPC |
| Next.js server | **No** Feed bootstrap API route; Feed page calls RPC from the **browser** | N/A |
| First-page dedupe | `loadFeedBootstrapForUser` → `readFeedBootstrapCache` + `beginFeedBootstrapFlight` (`lib/backendV2/feedBootstrapCache.ts`, `feedBootstrapSingleFlight.ts`) — **per tab, in-memory** | `FeedSessionStore` + `FeedBootstrapLoader` — **on-device** |
| Pagination | Cursor RPC; not written to first-page cache | Same |
| Typical scope | **Following** when session has follows (after `getSessionFollowingIds` / fetch); UI default state is `global` until resolved | Same product rules via loader |

**Implication:** k6 never hits browser or iOS caches. All k6 workloads are **PostgREST-facing**. The difference is *shape* (scope, mix, jitter, user spread), not HTTP hop through Vercel.

## Workloads in this repo

| Script / kind | Label | Represents |
|---------------|-------|--------------|
| `loadtest/prod-read-perf.js` + `LOADTEST_WORKLOAD_KIND=supabase_direct` | **Supabase direct stress** | Worst-case DB/API: global Feed first page, legacy 5-route mix, no startup jitter. **Web/iOS UX: no.** |
| `loadtest/prod-read-perf.js` + `LOADTEST_WORKLOAD_KIND=client_realistic` | **Client-realistic mix** | Following-first Feed, weighted Dashboard/Feed/Trades/Calendar/Profile, VU startup jitter, multi-user round-robin. **Web/iOS: approximate RPC mix and scope; still no cache hits.** |
| `loadtest/prod-read-perf.js` + `LOADTEST_PROD_PERF_MODE=realistic150` | **Realistic150 iOS** | 150 VUs on 50 accounts, ramp + sustain, screen TTL cache skips, idle/passive time. **See `loadtest/docs/PROD_PERF_REALISTIC150.md`.** |
| `loadtest/prod-read-perf.js` + `LOADTEST_PROD_PERF_MODE=realistic300` | **Realistic300 iOS** | Same `realistic150_ios` workload at 300 VUs on 50 accounts. **See `loadtest/docs/PROD_PERF_REALISTIC300.md`.** |
| `loadtest/prod-realistic300-full.js` | **Realistic300_full iOS** | Read mix + fixture-isolated messaging/Realtime at 300 VUs. **See `loadtest/docs/PROD_PERF_REALISTIC300_FULL.md`.** |
| `loadtest/prod-realistic600-full.js` | **Realistic600_full iOS** | Same workload at 600 VUs (informational thresholds). **See `loadtest/docs/PROD_PERF_REALISTIC600_FULL.md`.** |
| `loadtest/phase-a-read.js` (staging) | **Staging direct read** | Same PostgREST style as `supabase_direct` plus messages/leaderboard; staging-only gates. |

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `LOADTEST_WORKLOAD_KIND` | `supabase_direct` | Select workload column in the table above |
| `LOADTEST_FEED_SCOPE` | `following` (realistic) / `global` (direct) | Feed RPC `p_scope` |
| `LOADTEST_VU_START_JITTER_SEC` | `12` (realistic), `0` (direct) | Spread VU starts within each scenario |
| `LOADTEST_USERS_JSON` | — | **1–N** dedicated accounts; VUs round-robin (`(vuId-1) % N`). Use **≥1 user per 5 VUs** for realistic runs. |

No automatic user creation in production.

See also `loadtest/docs/FEED_RPC_OPTIMIZATION_NOTES.md` and `loadtest/PRODUCTION_READ_PERF.md`.
