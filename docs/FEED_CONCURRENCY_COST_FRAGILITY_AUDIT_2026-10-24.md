# TradeTraxs — Feed Concurrency, Costly Actions & Fragility Audit

**Date:** 2026-10-24  
**Mode:** Read-only (no code changes, builds, tests, or load tests).  
**Related audits:** [INFRASTRUCTURE_SCALABILITY_COST_AUDIT_2026-10-24.md](./INFRASTRUCTURE_SCALABILITY_COST_AUDIT_2026-10-24.md), [PRODUCT_ANALYTICS_OBSERVABILITY_TECH_DEBT_AUDIT_2026-10-24.md](./PRODUCT_ANALYTICS_OBSERVABILITY_TECH_DEBT_AUDIT_2026-10-24.md), [WEB_SUPABASE_PERFORMANCE_AUDIT.md](../WEB_SUPABASE_PERFORMANCE_AUDIT.md).

---

## 1. Executive summary

**Feed at scale:** Production Web Feed is **`backendV2.feed` ON** by default (`lib/backendV2/flags.ts`). A cold Feed open is designed around **one `rpc_v1_feed_bootstrap` call** per page-0 load (8 items), with **module-level single-flight** deduplication per user (`loadFeedBootstrapForUser`, `beginFeedBootstrapFlight`). iOS uses the same RPC when the feed flag is enabled, with **default limit 20** vs Web **8** (`FeedRpcBootstrapRepository.swift` vs `FEED_PAGE_SIZE = 8` in `lib/feedContent.ts`).

If **1,000 users open Feed at the same time** (cold cache, authenticated, Following mode, content filter “all”):

- **Confirmed request pattern:** ~**1,000–2,000 Supabase HTTP round-trips** in the first wave (mostly **1 RPC/user**; **+1** `fetchFollowingIds` possible on Web during global→following resolution).
- **Not deduplicated across users:** Single-flight is **per browser tab / user id**, not global.
- **First likely failures (ordered, no measured ceiling):** (1) **Postgres CPU / RPC latency** on `rpc_v1_feed_bootstrap`, (2) **Supabase pool wait** under burst, (3) **Realtime join latency** (~5 channels/user on Web Following), (4) **Storage egress** for avatars/thumbnails (~8+ objects/user if cache cold), (5) client **timeouts** and stale UI — not necessarily hard outage.

**Five most expensive user actions (infrastructure + direct $):** (1) **Broker full sync** (Tradovate/Rithmic), (2) **AI Trade Analyst** (`gpt-4o` + optional vision), (3) **Video/reel upload**, (4) **Leaderboard API rebuild** (service-role full public trade scan on cache miss), (5) **Analytics dashboard V3 bootstrap** / heavy owner trade reads.

**Ten most fragile areas:** Broker sync + worker SPOF, Stripe entitlements webhooks, Web Feed Realtime + insert hydration, messaging optimistic merge, community/trade rooms, profile/trades pagination RPCs, dashboard analytics dual paths, prop payout/financial RPCs, Backend V2 flag divergence, entitlement/billing client reconciliation.

**No precise concurrency limit is stated** — would require staging load tests (k6 script explicitly **does not** open Realtime; max documented VU **100** in `loadtest/README.md`).

---

## 2. Simultaneous Feed load — architecture trace

### 2.1 Web — cold open (authenticated, production flags)

| Step | Request / work | Evidence |
|------|----------------|----------|
| App shell (if cold app) | Profile, warm caches, Navbar unread, shared notification Realtime | [WEB_SUPABASE_PERFORMANCE_AUDIT.md](../WEB_SUPABASE_PERFORMANCE_AUDIT.md) — **not counted as Feed-only** |
| Following preflight (page 0, global default) | `getSessionFollowingIds` or **`fetchFollowingIds`**; may **switch mode** and **return before bootstrap** | `app/(app)/feed/page.tsx` ~1180–1200 |
| Feed page 0 load | **`loadFeedBootstrapForUser`** → **`rpc_v1_feed_bootstrap`** (`p_scope`, `p_content_filter`, `p_limit: 8`, optional `p_cursor`) | `feed/page.tsx` ~1208–1214; `feedBootstrapRepository.ts` |
| Cache | Module cache + single-flight per `(userId, scope, filter, cursor)` | `feedBootstrapCache.ts`, `beginFeedBootstrapFlight` |
| Engagement | Included in RPC payload (`feedBootstrapEngagementMaps`) — **no separate engagement fan-out** on V2 path | `feed/page.tsx` ~1274–1275 |
| Stories (Following) | **Embedded in bootstrap** (`bootstrap.data.stories`) | `feed/page.tsx` ~1226–1231 |
| Session snapshot | `persistFeedSnapshot` (sessionStorage) | `feed/page.tsx` ~1292+ |
| Realtime (Following, filter all/trades/posts/…) | Up to **5** `supabase.channel(...)` subscriptions: `feed-trade-posts`, `feed-profile-posts`, `feed-achievement-posts`, `feed-reels`, `feed-reel-likes` | `feed/page.tsx` ~1725–2066 |
| Realtime filter shape | `buildRealtimeInFilterChunks("user_id", followingIds)` — **100 ids/chunk** (`REALTIME_IN_FILTER_MAX_IDS`) | `lib/realtimeFilters.ts`; multiple `.on(postgres_changes)` **per channel** if following &gt; 100 |
| Realtime INSERT handler | **Extra REST read** per event (`posts.select…maybeSingle`) | `feed/page.tsx` ~1733–1737 (trade posts channel) |
| Media | Cards use **idle posters** for reels; **no video bytes** until intentional open (Backend V2 reel media program) | `docs/backend-v2/README.md` Reel media table |
| Images | Up to ~8 items × avatars/thumbs via Supabase **object/public** URLs (Next Image for web host) | `next.config.ts`, `lib/optimizedStorageImage.ts` |

**Legacy REST path:** Still implemented in `FeedRestBootstrapRepository` (following fetch + up to **4 batch queries + engagement maps + stories**) but **`loadFeedBootstrapForUser` throws if flag OFF** — production Feed **requires** V2 ON.

**Dual-run:** Development only doubles work (REST + RPC) when `NEXT_PUBLIC_BACKEND_V2_DUAL_RUN=1` (`feedBootstrapRepository.ts` ~521–534).

### 2.2 iOS — cold open

| Step | Request / work | Evidence |
|------|----------------|----------|
| Bootstrap entry | `FeedBootstrap.loadInitial` — timeline + stories **concurrent** | `FeedBootstrap.swift` ~78–83 |
| Timeline (V2 ON) | **`FeedBootstrapLoader.loadTimeline`** → **`rpc_v1_feed_bootstrap`** (default **limit 20**) | `FeedBootstrapRepository.swift`, `FeedScreenViewModel.swift` |
| Timeline (V2 OFF) | `DefaultFeedRepository.feed` — **4 parallel batches** + merge (legacy) | `DefaultFeedRepository.swift` ~79–100 |
| Stories (Following) | **`allActiveStories`** + profile hydration (separate from RPC if not using RPC-seeded stories path) | `FeedBootstrap.swift` ~139–167 |
| Disk | Feed first-page persistence + reconnect head reconcile (`performReconnectHeadReconcile`) | `FeedScreenViewModel.swift` ~834–894 |
| Realtime | Engagement/clips retention localized (`FeedClipsPagerView`); **central RealtimeHub** topic dedup on iOS vs **5 separate channels** on Web | `SupabaseProviders.swift` (infra audit) |

**Web vs iOS payload size:** Same RPC, but iOS often requests **20 rows** vs Web **8** → **higher DB work and JSON bytes per open** on iOS when flags align.

---

## 3. Estimated requests and Realtime connections (Feed-only wave)

Assumptions (labeled):

- **A1:** Each user = one client, one auth session, cold Feed module cache, page 0, Following + “all” content.
- **A2:** Shell/auth already warm (Feed tab switch only).
- **A3:** Average following count **50** (if **500**, Realtime adds more **postgres_changes bindings** per channel, not more HTTP on initial open).

| Concurrent Feed opens | Supabase HTTP (initial, Web) | Supabase HTTP (initial, iOS V2) | Realtime WS (clients) | Logical Realtime channels (Web, Following) | postgres_changes bindings (order-of-magnitude) |
|----------------------|------------------------------|----------------------------------|------------------------|--------------------------------------------|--------------------------------------------------|
| **100** | ~100–200 | ~100–200 (+ stories query if split) | ~100 | ~500 (5×100) | ~500+ (1 binding/chunk/channel type; 50 follows → 1 chunk each) |
| **500** | ~500–1,000 | ~500–1,000 | ~500 | ~2,500 | ~2,500+ |
| **1,000** | ~**1,000–2,000** | ~**1,000–2,000** | ~**1,000** | ~**5,000** | ~**5,000+** |
| **5,000** | ~5,000–10,000 | ~5,000–10,000 | ~5,000 | ~25,000 | ~25,000+ |

**Facts:**

- **1 RPC per cold user** on V2 path (`rpcRequestCount: 1` in load result).
- **Single-flight** collapses duplicate **same-user** concurrent loads only.

**Not included in table:** Navbar `notif-shared` channel, profile Realtime, CDN/storage GETs (~**8–20 images/user** if uncached), pagination (`p_cursor`) on scroll.

**Storage/CDN:** No separate CDN in repo — **Supabase Storage egress** scales with thumbnail/avatar fetches. Video **not** loaded on idle Feed cards (confirmed product rule).

---

## 4. First likely bottlenecks at ~1,000 concurrent Feed opens

| Order | Bottleneck | User experience | Evidence |
|-------|------------|-----------------|----------|
| 1 | **`rpc_v1_feed_bootstrap` compute** | Slow skeleton, long “loading feed”, p95 latency spike | Single heavy RPC replaces 7–12 REST calls but **concentrates** load; `20260820224542_rpc_v1_feed_bootstrap_optimize.sql` |
| 2 | **Postgres connection pool / PostgREST queue** | 5xx, “could not connect”, intermittent empty feed | Many independent clients; pool wait **not measured** in repo |
| 3 | **Realtime subscribe storm** | Live updates delayed; tabs feel “stuck” until refresh | 5 channels × 1000 clients; insert handlers add **N+1 REST** |
| 4 | **Storage egress / browser connection limits** | Broken avatars, slow paint | Many parallel image GETs |
| 5 | **Client JS main thread** (Web) | Jank on low devices | `feed/page.tsx` ~3313 LOC, merge/hydrate | 

**Failure cascade (theoretical):** RPC timeouts → retries (PostgREST transient retry **reads only** in profile bootstrap, **not** wired globally for Feed) → users refresh → **second RPC wave** amplifies load.

**What is unlikely to fail first:** Vercel serverless — **Feed data path is browser → Supabase directly**, not through Next API routes.

---

## 5. Five most expensive user actions (ranked)

Ranking uses **relative** cost (DB + serverless + bandwidth + external APIs). **Dollar estimates at 1,000 executions are intentionally omitted** (no billing data in repo); qualitative **Low / Medium / High / Very high** only.

### #1 — Broker account sync (Tradovate manual or auto; Rithmic import)

| Dimension | Assessment |
|-----------|------------|
| DB | **Very high** — fill ledger, executions, many trade upserts, sync status |
| Serverless / worker | **High** — Vercel routes up to **120s**; worker holds **WS per connection** |
| External API | **High** — Tradovate/Rithmic |
| Realtime | Low (optional trade cache refresh) |
| Bandwidth | Medium |
| **Per action** | **Very high** |
| **Continuous?** | **Yes** if auto-sync worker + active trading |

**Evidence:** `syncTradovateBrokerAccount.ts`, `persistBrokerTrades.ts`, `app/api/integrations/tradovate/.../sync/route.ts` (`maxDuration = 120`), `services/tradovate-sync-worker/run.ts`.

**At 1,000 executions:** Dominated by **external API quotas** and **Postgres write IO**; risk of **partial** status (`partial` sync) — not duplicate trades if unique indexes hold.

---

### #2 — AI Trade Analyst (`POST /api/analyze-trade`)

| Dimension | Assessment |
|-----------|------------|
| DB | Medium — read trade, write `trade_ai_messages` |
| Serverless | Medium — one Vercel invocation |
| External API | **Very high** — **`gpt-4o`**, optional **image_url** vision |
| **Per action** | **Very high** ($ dominated by OpenAI) |
| **Continuous?** | No (on demand) |

**Evidence:** `app/api/analyze-trade/route.ts` (`model: "gpt-4o"`), rate limit + entitlement helpers.

**At 1,000 runs:** **OpenAI bill** dominates; Supabase secondary.

---

### #3 — Upload reel / large video or multi-image post

| Dimension | Assessment |
|-----------|------------|
| DB | Low–medium — insert row + metadata |
| Storage | **Very high** — raw video bytes |
| Bandwidth | **Very high** — upload egress + later playback egress |
| Serverless | Low–medium (metadata API) |
| Client | Transcode/compress on iOS (`GlobalUploadCoordinator`) |
| **Per action** | **High–very high** |
| **Continuous?** | Playback is **continuous** cost for viewers |

**Evidence:** `GlobalUploadCoordinator.swift`, Supabase upload helpers, reel storage paths.

---

### #4 — Open Leaderboard (web) — cache miss

| Dimension | Assessment |
|-----------|------------|
| DB | **Very high** — service role **pages all public trades** (1000-row loops) |
| Vercel | Medium — one function, up to **60s** cache |
| **Per action** | **High** on miss; **low** on hit |
| **Continuous?** | No |

**Evidence:** `app/api/leaderboard/trades/route.ts` (`fetchViaKeysetRpc` while-loop, `LEADERBOARD_TRADES_REVALIDATE_SECONDS = 60`).

**At 1,000 concurrent users opening leaderboard:** Up to **1,000 cold rebuilds** if cache not shared across instances — **theoretical thundering herd** (mitigated by Next `unstable_cache` **if** shared cache layer hits).

---

### #5 — Dashboard analytics load (V3 bootstrap / full owner history paths)

| Dimension | Assessment |
|-----------|------------|
| DB | **High** — `rpc_v1_analytics_dashboard_v3_*`, `trade_daily_stats`, or **`rpc_v1_trades_owner_rows`** on Trades/Analyst |
| Client | Heavy JSON parse |
| GRDB (iOS) | Shadow/first paths — extra local work |
| **Per action** | **High** |
| **Continuous?** | Revisited on tab switch / filter change |

**Evidence:** Dashboard uses `analyticsHistory` (`app/(app)/dashboard/page.tsx`); Trades/Analyst still **`fullHistory: true`** (infra audit); analytics migrations `20260924120000_analytics_dashboard_v3_bootstrap.sql`.

**Honorable mentions (not top 5):** Messages **`rpc_v2_messaging_bootstrap`**, Explore bootstrap, **psychology-coach** OpenAI route, **data export** API, **weekly report push cron** (batch, not single-user action).

---

### One-time vs continuous cost

| Continuous / session-long | Episodic / one-shot |
|---------------------------|---------------------|
| Realtime subscriptions (Feed, messages, rooms) | Broker sync run |
| Auto Tradovate worker connections | AI analysis |
| Video **playback** after open | Feed page 0 RPC |
| Leaderboard cache refresh background | Tax CSV export modal |

---

## 6. Ten most fragile features (ranked)

| Rank | Feature | Fragility | Likelihood | Impact | Data risk | Key evidence |
|------|---------|-----------|------------|--------|-----------|--------------|
| 1 | **Tradovate auto-sync + manual sync** | **Very high** | Medium–high | Missing trades, stale journal | Partial imports; dupes unlikely | Worker SPOF (`BROKER_SYNC_WORKER.md`); `brokerIntegrationSync.ts`; infra §13 |
| 2 | **Stripe / Apple entitlements** | **Very high** | Medium | Wrong Pro state | Under/over access | Webhook **200 on failure**; `syncMembershipAfterStripeCheckout.ts` |
| 3 | **Web Feed (Following) Realtime** | **High** | Medium | Stale/missing posts; duplicate hydrate if race | Mostly display | 5 channels; INSERT → extra SELECT (`feed/page.tsx`) |
| 4 | **DM / Messages thread** | **High** | Medium | Failed send, duplicate bubble edge cases | Display; rare dup | `optimisticMessage.ts`; large `messages/[id]/page.tsx` (~4683 LOC) |
| 5 | **Trade Rooms / Community** | **High** | Medium | Unread, moderation actions wrong | Moderation audit | `community/page.tsx` ~5728 LOC; `communityRoomUnread.ts`; new **`20261024163000_trade_room_moderator_permissions.sql`** |
| 6 | **Profile + trades tab pagination (V2 RPC)** | **High** | Medium | Wrong page, privacy leak if RPC bug | Display | `rpc_v1_profile_tab_trades_v2` migrations + security tests |
| 7 | **Dashboard / calendar analytics** | **High** | Medium | Charts mismatch vs trades | Display | GRDB shadow + RPC dual path (`Data/Analytics/Local/README.md`); web `analyticsHistory` vs `fullHistory` split |
| 8 | **Prop firm payouts / expenses / income** | **Medium–high** | Low–medium | Balance wrong after delete | **Financial** | `delete_prop_payout` PL/pgSQL (`20261024043000_...sql`); multi-step client flows |
| 9 | **Social engagement (TradeSocialLayer / likes)** | **Medium–high** | Medium | Wrong counts | Display | WEB audit: Realtime → **full like refetch** |
| 10 | **Backend V2 flag matrix (Web/iOS)** | **Medium–high** | Ongoing | Divergent behavior | Varies | `flags.ts` — feed/messages ON, many OFF; iOS limit 20 vs web 8 |

For each, **recommended focused improvement** is in §8.

---

## 7. Highest-risk dependency chains

```
Feed Following (Web)
  → auth session (Supabase Auth)
  → rpc_v1_feed_bootstrap (Postgres + RLS)
  → 5× Realtime postgres_changes (Supabase Realtime)
  → on INSERT → PostgREST row hydrate
  → Storage GET (media)

Broker auto-sync
  → tradovate-sync-worker (always-on)
  → Tradovate WebSocket + OAuth token refresh
  → syncTradovateBrokerAccount (Vercel-capable code path)
  → broker_integration_executions + trades upsert
  → optional Realtime → web trade cache

Checkout → Pro
  → Stripe Checkout
  → webhook → profiles.is_pro
  → client poll syncMembershipAfterStripeCheckout
  → /api/billing/entitlement (canonical snapshot)

Trade Room moderation (new)
  → room_members + moderator permissions (RLS/RPC)
  → room_messages insert
  → notify API → NotificationService → APNs
```

Any break in **worker**, **webhook**, or **RLS policy** surfaces as **silent degradation** (missing data) rather than hard error.

---

## 8. Top five improvements (reliability + cost)

| # | Improvement | Feeds 1k concurrency? | Cost? | Effort |
|---|-------------|------------------------|-------|--------|
| 1 | **Multiplex Web Feed Realtime** to one channel / shared hub (iOS pattern) | **Yes** — fewer joins, simpler lifecycle | Medium | M |
| 2 | **RPC read replica / scale Postgres compute** + monitor `rpc_v1_feed_bootstrap` p95 | **Yes** | Medium | S–M (ops) |
| 3 | **Edge/cache leaderboard** — materialized table, stop full-table scan | No (leaderboard) | **Yes** | M |
| 4 | **Stripe webhook 5xx + idempotent entitlement RPC** | No | Revenue | S–M |
| 5 | **Broker worker HA + heartbeat alerts** | No | Sync reliability | S |

Additional Feed-specific: **remove INSERT→full-row refetch** (use payload.new where safe); **align iOS limit 20 → 8** for parity under load (product tradeoff).

---

## 9. Confidence and missing production metrics

| Claim | Confidence | What would validate |
|-------|------------|---------------------|
| 1 RPC / user Feed V2 cold open | **High** | Code path |
| 5 Realtime channels / Web Following user | **High** | `feed/page.tsx` |
| First bottleneck = RPC/Postgres | **Medium** | Supabase query stats, p95 RPC latency at 100 VU k6 |
| 1000 concurrent feasible on current plan | **Low** | Load test + pool metrics |
| $ cost at 1000 AI/sync runs | **Low** | OpenAI + Supabase invoices |
| Realtime limits at 5k channels | **Low** | Supabase Realtime dashboard |

**Existing load test:** `loadtest/phase-a-read.js` — includes **`rpc_v1_feed_bootstrap` (8 items)** but **no Realtime**, max **100 VU**, staging only.

---

## Appendix — File index

| Topic | Path |
|-------|------|
| Web Feed load | `app/(app)/feed/page.tsx` |
| Feed RPC loader | `lib/backendV2/feedBootstrapRepository.ts` |
| Page size | `lib/feedContent.ts` (`FEED_PAGE_SIZE = 8`) |
| Feed flag default | `lib/backendV2/flags.ts` |
| Realtime chunks | `lib/realtimeFilters.ts` |
| iOS Feed bootstrap | `native-ios/.../FeedBootstrap.swift`, `FeedScreenViewModel.swift` |
| iOS Feed REST fallback | `DefaultFeedRepository.swift` |
| iOS RPC limit | `FeedBootstrapRepository.swift` |
| Broker sync | `syncTradovateBrokerAccount.ts`, worker `run.ts` |
| AI cost | `app/api/analyze-trade/route.ts` |
| Leaderboard cost | `app/api/leaderboard/trades/route.ts` |
| Upload resilience | `GlobalUploadCoordinator.swift` |

---

*End of report.*
