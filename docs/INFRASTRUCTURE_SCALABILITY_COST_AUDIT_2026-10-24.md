# TradeTraxs Infrastructure Scalability, Capacity & Cost Audit

**Date:** 2026-10-24  
**Mode:** Read-only repository investigation — no code changes, builds, tests, or load tests were run.  
**Scope:** Web (Next.js), native iOS, Supabase, Vercel, broker integrations (Tradovate, Rithmic), push, crons, and third-party services referenced in the repo.

---

## 1. Executive summary

TradeTraxs is a **Supabase-centric** product: browsers and iOS talk to **PostgREST/RPC and Realtime** directly for most product data, with **~100 Next.js API routes** on Vercel for BFF tasks (billing, push, notifications, broker OAuth/sync, AI, admin, crons). Media lives in **Supabase Storage** (object/public URLs; **Image Transformations disabled** in code). **Tradovate auto-sync requires a separate long-lived worker** (`services/tradovate-sync-worker/`), explicitly **not** deployed on Vercel.

**Confirmed strengths:** Extensive **bootstrap RPC program** (session, dashboard, feed, messaging, profile, rooms, analytics daily range via `trade_daily_stats`), **Phase 3 hot-path indexes**, iOS **RealtimeHub + topic deduplication** (`SupabaseProviders.swift`), iOS **GRDB shadow/first analytics** (flags mostly Release-OFF), feed/messages Backend V2 **default ON**, dashboard/calendar moved to **`analyticsHistory`** (narrow trade projection) instead of full journal rows, community room unread **event-driven** (no 60s poll in `lib/communityRoomUnread.ts`).

**First likely bottlenecks as usage grows (ordered):**

1. **Per-user database read amplification** — full owner trade history via `rpc_v1_trades_owner_rows` on Trades/Analyst (`fullHistory: true`); leaderboard API still **pages all public trades** into memory on cache miss (`app/api/leaderboard/trades/route.ts`).
2. **Supabase Realtime fan-out** — Web Feed alone can hold **up to ~5+ postgres_changes channels** per active tab (`app/(app)/feed/page.tsx`); concurrent WebSocket clients scale with **active sessions**, not registered users.
3. **Supabase Postgres compute + connection pressure** — many parallel REST/RPC calls per cold session (documented ~15–22 in [WEB_SUPABASE_PERFORMANCE_AUDIT.md](../WEB_SUPABASE_PERFORMANCE_AUDIT.md)); pool wait was **never measured** in repo docs.
4. **Media storage & egress** — reels/video and screenshots served as **full objects** (`lib/optimizedStorageImage.ts`); heavy social users dominate bandwidth.
5. **Broker worker scale** — **one WebSocket per connected Tradovate OAuth connection** on a **single worker instance** (docs warn: scale to 1 unless distributed locking); Rithmic sync/import runs on **Vercel serverless** up to **120s** (`maxDuration`).
6. **Notification + APNs fanout** — room/DM events invoke serverless orchestration (`lib/server/notifications/NotificationService.ts`) and direct APNs (`lib/server/push/apns.ts`).

**Cost outlook (assumption-based):** At **100 MAU**, infrastructure likely fits **Supabase Pro + Vercel Pro/Hobby + minimal worker + Sentry** (~**$50–150/mo** all-in depending on media). At **1K–10K MAU**, **database compute, Realtime connections, storage egress, and Vercel function GB-seconds** become the dominant variables; at **100K MAU**, **architectural changes** (aggregates, leaderboard materialization, Realtime consolidation, CDN for media, read replicas / larger Supabase tier) are likely **before** pure plan upgrades suffice.

**Confidence:** Architecture and hot paths are **high confidence** (code + migrations). Absolute user capacity and dollar costs are **low–medium confidence** without production metrics (listed in §10).

**Resilience (§13–§14):** iOS has structured **offline UX**, **GlobalUpload** checkpoints, and **Realtime reconnect repair**; Web relies on **in-memory/sessionStorage caches** and limited automatic retry. **Broker sync** uses DB locks, lifecycle keys, and execution uniqueness — **duplicate trades are unlikely** if constraints hold. **Stripe webhooks** often return **HTTP 200 even when handlers fail**, which can **block Stripe retries**; client **checkout reconciliation polling** partially mitigates. **No circuit breakers** and **no in-repo backup/runbook** documentation were found.

---

## 2. Current architecture and infrastructure inventory

### 2.1 Logical architecture

```
┌─────────────────┐     ┌─────────────────┐
│  Web browser    │     │  iOS (SwiftUI)  │
│  Next.js 16     │     │  RealtimeHub    │
│  client-side    │     │  GRDB analytics │
│  Supabase JS    │     │  (shadow/first) │
└────────┬────────┘     └────────┬────────┘
         │  HTTPS (REST/RPC/Realtime WS)
         │  HTTPS (selected BFF APIs)
         ▼
┌────────────────────────────────────────────┐
│ Supabase (single project — ref in loadtest) │
│  PostgreSQL + RLS + RPC bootstraps          │
│  Auth (JWT)                                 │
│  Storage (images, reels, voice, etc.)       │
│  Realtime (postgres_changes publication)    │
└────────────────────────────────────────────┘
         ▲
         │ service role
┌────────┴────────┐     ┌──────────────────────┐
│ Vercel          │     │ tradovate-sync-worker │
│ ~100 API routes │     │ (Docker / always-on)  │
│ 3 crons         │     │ 1 WS / connection     │
└────────┬────────┘     └──────────────────────┘
         │
    Stripe, OpenAI, APNs, Sentry, Vercel Analytics
```

**Evidence:** `package.json` (Next 16.2.3, `@supabase/supabase-js`), `vercel.json` crons, `services/tradovate-sync-worker/run.ts`, `loadtest/README.md` (production ref `fobudrkniacatvilbofw` blocked for load tests).

### 2.2 Web application (Vercel)

| Item | Detail | Evidence |
|------|--------|----------|
| Framework | Next.js App Router, mostly `"use client"` product pages | [WEB_SUPABASE_PERFORMANCE_AUDIT.md](../WEB_SUPABASE_PERFORMANCE_AUDIT.md) §2 |
| API surface | ~100 `app/api/**/route.ts` handlers | repo glob |
| Crons | Daily Apple revoke; daily expired stories; weekly trading report push | `vercel.json` |
| Cron auth | `CRON_SECRET` bearer | e.g. `app/api/cron/weekly-trading-reports/route.ts` |
| Long jobs | Broker/Rithmic import/sync `maxDuration = 120`; internal probe `300` | grep `maxDuration` in `app/api` |
| Observability | Sentry (`@sentry/nextjs`, `instrumentation.ts`) | `next.config.ts`, `sentry.server.config.ts` |
| Analytics | `@vercel/analytics`, `@vercel/speed-insights` | `package.json` |
| Images | Next Image for Supabase host; **no Supabase render/transform** | `next.config.ts`, `lib/optimizedStorageImage.ts` |

**Hosting plan tier:** **Not specified in repository** — treat Vercel/Supabase plan sizes as **unknown**; cost section uses public list pricing as **assumptions**.

### 2.3 Supabase / PostgreSQL

| Item | Detail | Evidence |
|------|--------|----------|
| Access pattern | Browser/iOS anon/authenticated JWT → PostgREST + `.rpc()` | `lib/supabaseClient.ts`, iOS `SupabaseTransport.swift` |
| Bootstrap RPCs | `rpc_v1_session_bootstrap`, `rpc_v1_dashboard_bootstrap`, `rpc_v1_feed_bootstrap`, `rpc_v2_messaging_bootstrap`, profile/room/thread bootstraps, `rpc_v1_analytics_daily_range_bootstrap` | migrations under `supabase/migrations/`; `docs/backend-v2/README.md` |
| Owner trades | `rpc_v1_trades_owner_rows` (optional `p_limit`, `p_trade_ids`) | `lib/tradeOwnerRead.ts` |
| Analytics grain | `trade_daily_stats` + `user_analytics_state` (realtime publication on state) | `20260923230000_rpc_v1_analytics_daily_range_bootstrap_optimize.sql`, `20260924160000_user_analytics_state_realtime_publication.sql` |
| Indexes | Hot paths: comments, followers, notifications, posts, messaging cursors, trades user+created_at, etc. | `20260804230000_phase3_hot_path_indexes.sql`, earlier phase migrations |
| RLS | Broad `auth.uid()` usage (534+ refs per Aug audit); scalar subquery optimization **not** applied repo-wide | [WEB_SUPABASE_PERFORMANCE_AUDIT.md](../WEB_SUPABASE_PERFORMANCE_AUDIT.md) §10 |
| Realtime policy | Some watches disabled client-side (`stories`, profile/achievement post likes); publication **candidates** documented | `lib/realtimePublicationPolicy.ts` |
| Broker tables | `broker_integration_connections`, account sync, listener heartbeat columns | `20260914270000_broker_auto_sync.sql`, worker heartbeat migration referenced in docs |

### 2.4 Native iOS

| Item | Detail | Evidence |
|------|--------|----------|
| Data | Shared Supabase project; BFF for billing, push register, some integrations | `native-ios/ARCHITECTURE.md` |
| Realtime | `RealtimeHub` + `LiveSupabaseRealtimeProvider` — **route-level topic dedup** (`joinedTopics`) | `RealtimeArchitecture.swift`, `SupabaseProviders.swift` |
| Local cache | GRDB for analytics shadow / optional first-read (Release flags OFF for dashboard/calendar GRDB-first) | `Data/Analytics/Local/README.md` |
| Performance policy | No full trade history on launch; disk-first feed | `native-ios/ARCHITECTURE.md` §11–12 |
| Push | APNs token registration via `/api/push/register` | `app/api/push/register/route.ts` |

### 2.5 Broker integrations

| Provider | Runtime | Sync model | Evidence |
|----------|---------|------------|----------|
| **Tradovate** | OAuth on Vercel; **auto-sync on worker** | WebSocket `user/syncrequest`; debounced `syncTradovateBrokerAccount()` (1.5s coalesce) | `docs/tradovate/BROKER_SYNC_WORKER.md`, `tradovate-sync-worker/run.ts` |
| **Rithmic** | Vercel serverless (WSS + protobuf assets bundled) | Connect/import/sync routes, up to 120s | `next.config.ts` `outputFileTracingIncludes`, Rithmic API routes |
| Manual sync | Same canonical sync function as worker | `lib/integrations/tradovate/syncTradovateBrokerAccount.ts` comment |

Worker heartbeat stale threshold: **90s** (`TRADOVATE_WORKER_HEARTBEAT_STALE_MS` in `lib/integrations/tradovate/tradovateListenerStatus.ts`).

### 2.6 Notifications & push

- **In-app:** `notifications` table + Realtime (`lib/notificationRealtime.ts`).
- **Server fanout:** `NotificationService.notify()` — likes, comments, DMs, room messages, trading reports, affiliate events (`lib/server/notifications/NotificationService.ts`).
- **Push:** Direct **APNs HTTP/2** (`lib/server/push/apns.ts`); device rows in `device_push_tokens`.
- **Client-triggered API routes:** e.g. `app/api/notifications/room-message/route.ts` after send.

### 2.7 AI & other paid APIs

| Service | Usage | Cost control |
|---------|-------|--------------|
| **OpenAI** | `analyze-trade`, `psychology-coach`, `trade-import/screenshot-extract` | Entitlement + durable rate limits on analyze; `ai-chat` **disabled (404)** | 
| **Stripe** | Checkout, portal, webhooks, Connect affiliates | Standard API usage |
| **Apple** | StoreKit + `/api/apple/subscription/*` | Server library in deps |

### 2.8 Monetization (affects load, not assumed enabled)

- TraxPro via Stripe + Apple (`lib/traxProPriceCatalog.ts`, StoreKit).
- Free plan DB enforcement hooks (e.g. daily trade/clip limits when `free_plan_limits_enforced()`) — `20260929150000_monetization_runtime_config.sql`.
- **Subscription conversion for margin math:** modeled scenarios only; **not assumed live**.

### 2.9 Load testing artifact (not executed in this audit)

- `loadtest/phase-a-read.js` — k6 read paths up to **100 VU**, **no Realtime**, staging-only.
- Thresholds: p95 &lt; 2–5s on tagged pages; documents RPCs called per “virtual session.”

---

## 3. User scale definitions

| Term | Definition used in this report |
|------|--------------------------------|
| **Registered users** | Rows in `auth.users` / `profiles` |
| **MAU** | Distinct users with ≥1 authenticated session in 30 days |
| **DAU** | Distinct users with ≥1 session in 24 hours |
| **Concurrent users** | Simultaneous active clients (HTTP and/or Realtime WS) — **peak** metric; typically **≪ DAU** |

**Assumption (not measured):** For a trading + social app, **DAU/MAU ≈ 25–40%** and **peak concurrent ≈ 3–8% of DAU** during market hours is a reasonable planning range. Actual ratios require production analytics.

---

## 4. Capacity assessment by scale

Legend: **Pressure** (Low / Moderate / High / Severe) · **Architecture sufficient?** (Yes / Marginal / No) · **Confidence** (H/M/L)

### 4.1 ~100 MAU (~25–40 DAU, ~1–3 peak concurrent web+iOS)

| Dimension | Expected pressure | Likely bottleneck | Sufficient? | Before next scale | Conf. |
|-----------|-------------------|-------------------|-------------|-------------------|-------|
| Postgres | Low | None at this size | Yes | Monitor `trade_daily_stats` freshness | M |
| Realtime | Low | Few dozen WS max | Yes | — | M |
| Vercel | Low | Cold starts on broker import | Yes | — | H |
| Storage/bandwidth | Low–Moderate | Reels if creators upload | Yes | — | M |
| Broker worker | Low | Forgotten worker deploy | Marginal if Tradovate users expect auto-sync | Run 1 worker instance | H |

**Notes:** Cold bootstrap fan-out is noticeable per user but negligible aggregate. k6 staging script targets this tier (`LOADTEST_MAX_VUS=10` first).

### 4.2 ~1,000 MAU (~250–400 DAU, ~10–30 peak concurrent)

| Dimension | Expected pressure | Likely bottleneck | Sufficient? | Before next scale | Conf. |
|-----------|-------------------|-------------------|-------------|-------------------|-------|
| Postgres | Moderate | Power users: `rpc_v1_trades_owner_rows` full pull; leaderboard rebuild | Marginal | Cap/limit owner rows on Trades; materialize leaderboard | M |
| Realtime | Moderate | Web feed 5× channels × active feed viewers | Marginal | Multiplex feed Realtime (iOS-style) | M |
| Vercel | Moderate | Notification + push on active social graph | Yes | Watch function duration on room notify | M |
| Storage/bandwidth | Moderate | Video egress | Marginal | CDN or transcoded renditions | L |
| Broker worker | Moderate | N connections × 1 WS | Yes (single worker) | Monitor CPU/memory; plan 2nd worker + locking | M |

**First cross-tier bottleneck:** **Heavy journal users** + **leaderboard cache miss** on Vercel (service role scans all public trades).

### 4.3 ~10,000 MAU (~2.5–4k DAU, ~100–300 peak concurrent)

| Dimension | Expected pressure | Likely bottleneck | Sufficient? | Before next scale | Conf. |
|-----------|-------------------|-------------------|-------------|-------------------|-------|
| Postgres | High | Connection pool wait; RLS CPU on wide selects | **No** without tuning | Larger compute; `(select auth.uid())`; reduce client fan-out; enable more Backend V2 flags | M |
| Realtime | High | Supabase Realtime connection limits (plan-dependent) | **Marginal** | Consolidate channels; reduce postgres_changes tables watched | L |
| Vercel | High | Cron fanout (weekly reports); social notify bursts | Marginal | Queue workers for push; batch cron | M |
| Storage/bandwidth | High | Reels | **No** for cost | Object lifecycle, compression, CDN | M |
| Broker worker | High | Single process ceiling | **No** | Horizontal workers + distributed lease on connections | M |

**Architecture gap:** Web still loads **many parallel queries** when Backend V2 flags remain OFF (dashboard, profile, session default OFF in `lib/backendV2/flags.ts`).

### 4.4 ~100,000 MAU (~25–40k DAU, ~1k–3k peak concurrent)

| Dimension | Expected pressure | Likely bottleneck | Sufficient? | Before next scale | Conf. |
|-----------|-------------------|-------------------|-------------|-------------------|-------|
| Postgres | Severe | Row volume on `trades`, `messages`, `room_messages`, `notifications` | **No** | Partition/archival; read replicas; pre-aggregates; strict pagination everywhere | M |
| Realtime | Severe | WS connection count | **No** | Presence via Realtime sparingly; inbox-driven updates; optional dedicated Realtime tier | L |
| Vercel | Severe | API route fanout | **No** | Move heavy jobs off serverless; edge caching for public reads | M |
| Storage/bandwidth | Severe | Video | **No** | Dedicated media pipeline (transcode + CDN) | M |
| Broker worker | Severe | Tradovate connection count | **No** | Sharded workers; connection assignment | M |

**Do not claim** “supports 100k concurrent users” — repo contains **no** production proof of Realtime or pool headroom at this tier.

---

## 5. First likely bottlenecks (cross-cutting)

1. **`rpc_v1_trades_owner_rows` without limit** on Trades/Analyst (`app/(app)/trades/page.tsx`, `app/analyst/page.tsx` — `fullHistory: true`). Dashboard/Calendar use **`analyticsHistory: true`** (narrower) — improvement vs Aug 2026 audit.
2. **Leaderboard service-role full scan** — `fetchViaKeysetRpc` loops until exhaustion, 60s Next cache (`app/api/leaderboard/trades/route.ts`).
3. **Web Realtime channel multiplication** — Feed: separate channels for trade posts, profile posts, achievements, reels, reel likes ([WEB_SUPABASE_PERFORMANCE_AUDIT.md](../WEB_SUPABASE_PERFORMANCE_AUDIT.md) §5; still present in `feed/page.tsx` grep).
4. **Cold session bootstrap fan-out** — Profile + warm + Getting Started + Navbar unread chain (~15–22 calls) when caches cold.
5. **Supabase Storage full-file delivery** for video/images — no transform CDN in app (`lib/optimizedStorageImage.ts` header comment).
6. **Tradovate worker single-instance** — docs explicitly say scale to 1 without locking (`docs/tradovate/BROKER_SYNC_WORKER.md`).
7. **Rithmic on Vercel** — 120s cap; concurrent imports during market open could throttle or fail.
8. **Social notification path** — each message/like can hit Vercel + DB + APNs (`NotificationService`).
9. **RLS initplan cost** — hundreds of policies using bare `auth.uid()` (static audit finding).
10. **`TradeSocialLayer` Realtime → full like refetch** (still cited in Aug audit; verify in prod usage on feed/trade cards).

---

## 6. Request & subscription patterns (by surface)

Estimates combine [WEB_SUPABASE_PERFORMANCE_AUDIT.md](../WEB_SUPABASE_PERFORMANCE_AUDIT.md) (web, updated where code changed) + iOS architecture docs + `loadtest/phase-a-read.js`.

| Surface | Web REST/RPC (typical cold → warm) | Realtime (web) | iOS notes |
|---------|-------------------------------------|----------------|-----------|
| **Dashboard** | 2–4 → 0–2; analytics via cache/RPC not full journal | Shell notif + profile | GRDB-first optional (Release OFF) |
| **Feed** | 1–2 with `rpc_v1_feed_bootstrap` ON; else 7–12 | Up to **5+** channels | Bootstrap + engagement in RPC when ON |
| **Profile** | 6–12 | Reel likes channel | Profile bootstrap RPC when flag ON |
| **Trades** | 2–3 + **full owner rows RPC** | Shell | Avoids full history on launch (policy) |
| **Messages** | 1 with `rpc_v2_messaging_bootstrap` ON; else ~5 | 1 thread channel | `MessagingDomain` consolidated realtime |
| **Rooms / Community** | 6–8 + room messages | Room live + typing + unread filters | `watchRoomLive`, member room multiplex |
| **Analytics / Calendar** | `analyticsHistory` / daily range RPC | Optional `user_analytics_state` | Calendar V2 RPC → `trade_daily_stats` |
| **Leaderboard** | 1 API → server aggregates **all public trades** | — | BFF + cached DTO |

**Concurrent Realtime:** Plan for **1 WS per client** (Supabase multiplexes channels). Web Feed + Messages + Community can push **10+ logical channels** per highly active user if screens overlap.

---

## 7. Infrastructure cost estimates (monthly)

**All dollar amounts below are modeled assumptions** using typical 2026 public pricing for Supabase/Vercel/OpenAI/Sentry/Railway-class worker hosting. **Your actual plans, credits, and egress are not in the repo.**

### 7.1 Usage scenarios (per MAU, per month)

| Scenario | Sessions/mo | Supabase REST/RPC calls | Realtime minutes | Storage (per user) | Broker | Media consumption |
|----------|-------------|-------------------------|------------------|--------------------|--------|-------------------|
| **Light** | 8 | ~200 | 30 | 50 MB | None | Low images |
| **Typical** | 25 | ~800 | 120 | 200 MB | Tradovate manual + occasional auto | Some reels |
| **Heavy** | 60 | ~2,500+ | 400+ | 1 GB+ | Auto-sync + multiple accounts | Daily video |

### 7.2 Fixed baseline (assumption)

| Service | Assumed baseline |
|---------|------------------|
| Supabase Pro | ~$25/mo + compute addon |
| Vercel Pro (team) | ~$20/mo + usage |
| Sentry | ~$0–26/mo (team size dependent) |
| Broker worker (1× small VM) | ~$5–15/mo |
| Apple Developer | ~$8/mo amortized |
| OpenAI | **Usage-only** (heavy AI users dominate) |

### 7.3 Estimated monthly total cost

| MAU | Light mix (90/9/1%) | Typical mix (70/25/5%) | Heavy mix (50/40/10%) |
|-----|---------------------|-------------------------|------------------------|
| **100** | $80–120 | $100–180 | $150–350 |
| **1,000** | $150–300 | $300–700 | $600–1,500 |
| **10,000** | $600–1,200 | $1,500–4,000 | $4,000–12,000+ |
| **100,000** | $5k–10k | $15k–40k | $50k–150k+ |

**Cost per MAU (typical mix, rounded):**

| MAU | ~$/MAU/mo |
|-----|-----------|
| 100 | $1.00–1.80 |
| 1,000 | $0.30–0.70 |
| 10,000 | $0.15–0.40 |
| 100,000 | $0.15–0.40 (economies of scale if optimized; else higher) |

### 7.4 Major cost drivers by tier

| Tier | Drivers likely to exceed included quotas |
|------|----------------------------------------|
| 100 MAU | Egress if reels go viral; OpenAI on power users |
| 1K MAU | Supabase **egress + storage**; Vercel **function GB-sec** on notifications |
| 10K MAU | **Postgres compute**; **Realtime** peak connections; media egress |
| 100K MAU | All above + **leaderboard/trade table size** (storage + backup + query IO) |

### 7.5 Cost-saving improvements (highest ROI)

1. **Stop shipping full trade history** to Trades/Analyst clients — use paginated RPC + on-disk aggregates (already partially done for dashboard).
2. **Materialized leaderboard** — avoid full public trade pull on every cache miss.
3. **Media:** upload-time compression (partially present via `/opt/` paths), optional CDN in front of Storage.
4. **Enable remaining Backend V2 bootstraps in production** — fewer round trips (flags default OFF except feed/messages).
5. **Consolidate Web Realtime** — match iOS topic sharing.
6. **AI:** keep `ai-chat` disabled; tighten rate limits on vision routes.

---

## 8. Gross margin scenarios (subscription not assumed enabled)

**Assumption:** TraxPro price **~$15–30/mo equivalent** (Stripe catalog is dynamic — `app/api/billing/prices/route.ts`).

| MAU | Conv. rate | Paying users | Revenue/mo (@ $20 ARPU) | Infra (typical mix) | Gross margin (infra only) |
|-----|------------|--------------|-------------------------|---------------------|---------------------------|
| 1,000 | 2% | 20 | $400 | ~$500 | **Negative** without optimization |
| 1,000 | 8% | 80 | $1,600 | ~$500 | ~69% |
| 10,000 | 5% | 500 | $10,000 | ~$2,500 | ~75% |
| 10,000 | 15% | 1,500 | $30,000 | ~$3,500 | ~88% |
| 100,000 | 5% | 5,000 | $100,000 | ~$25,000 | ~75% |

**Excludes:** payroll, support, Apple 15–30% cut on iOS IAP, Stripe fees, tax, Tradovate/Rithmic partner costs, OpenAI variable margin hit on AI-heavy plans.

**Heavy-user skew:** 10% of users driving 50%+ of infra cost is plausible (video + broker + full history); conversion must outrun heavy tail or limits (free plan DB limits exist but may be toggled — `free_plan_limits_enforced()`).

---

## 9. Top 10 scalability and cost risks

| # | Risk | Why it hurts | Evidence |
|---|------|--------------|----------|
| 1 | Full owner trade RPC on key pages | DB IO + payload size scales with lifetime trades | `trades/page.tsx`, `analyst/page.tsx`, `rpcTradesOwnerRows` |
| 2 | Leaderboard full rebuild | CPU + memory on Vercel; DB read amp | `app/api/leaderboard/trades/route.ts` |
| 3 | Realtime connection growth | Plan limits; unstable WS under load | Web feed channels; Supabase Realtime |
| 4 | Postgres pool exhaustion | Latency cascades on cold bootstrap | Aug audit W1; many parallel client queries |
| 5 | Media egress | Dominates bill at social scale | Storage public URLs, reels |
| 6 | Broker worker SPOF | Auto-sync stops; manual sync spikes Vercel | `BROKER_SYNC_WORKER.md` |
| 7 | Rithmic serverless time limits | Failed imports; retries multiply cost | `maxDuration = 120` on import routes |
| 8 | Notification storms | Function + APNs + DB writes | `NotificationService`, room-message API |
| 9 | RLS CPU at row scale | Policy eval per row | Migration grep `auth.uid()` |
| 10 | Backend V2 partial rollout | Web keeps legacy fan-out | `flags.ts` defaults |

---

## 10. Recommended improvements (impact × effort)

| Rank | Change | Impact | Effort | Evidence |
|------|--------|--------|--------|----------|
| 1 | Paginate/limit Trades/Analyst owner reads; server aggregates for analytics | High | Medium | `fullHistory` vs `analyticsHistory` split in `appDataCache.ts` |
| 2 | Precomputed leaderboard table / incremental refresh | High | Medium | Leaderboard API while-loop |
| 3 | Multiplex Web Feed Realtime (1 channel / shared hub) | High | Medium | iOS `joinedTopics` pattern |
| 4 | Production-enable session + dashboard + profile Backend V2 after validation | High | Low–Med | `lib/backendV2/flags.ts` |
| 5 | Materialize/navbar badge RPC (single hop) | Med | Low | Aug audit W7 |
| 6 | CDN or multi-bitrate video | High (cost) | High | `optimizedStorageImage.ts` |
| 7 | Broker worker sharding + connection lease | Med–High | High | Worker docs “scale to 1” |
| 8 | Queue for push/notify (SQS/Supabase queue/cron batch) | Med | Med | Room notify path |
| 9 | RLS hot-policy `(select auth.uid())` rewrite | Med | Med | Aug audit R1 |
| 10 | TradeSocial like count without full row fetch | Med | Low | Aug audit §5 |

---

## 11. Metrics needed to validate estimates

Production instrumentation should answer:

| Metric | Validates |
|--------|-----------|
| Supabase **Dashboard**: CPU, memory, disk IO, active connections, pool wait | Postgres bottleneck timing |
| **pg_stat_statements** top 20 by total_time | RPC vs REST hotspots |
| **Realtime** concurrent connections & channel count | WS limit planning |
| **Egress + storage** by bucket (`reels`, avatars, trade screenshots) | Media cost |
| Vercel **function duration / invocations** by route (`notifications/*`, `integrations/*`) | Serverless cost |
| Client **RUM**: TTFB per screen, bootstrap request count (Backend V2 telemetry exists — `lib/backendV2/telemetry.ts`) | Fan-out reduction proof |
| **DAU/MAU**, session length, **peak concurrent** (analytics) | Scale table calibration |
| Broker: connections per worker, sync duration, error rate | Worker sizing |
| APNs success/failure + invalid token rate | Push cost & hygiene |
| OpenAI tokens per MAU | AI margin |

**Existing tooling:** k6 Phase A (reads, no Realtime); iOS `SessionNetworkProbe`, `RealtimeLifecycleDebugLog`, `realtimePressureSnapshot()`.

---

## 12. Fact vs estimate vs unknown

| Category | Examples |
|----------|----------|
| **Confirmed (repo)** | Vercel crons; worker not on Vercel; feed/messages V2 default ON; Tradovate 90s heartbeat; production Supabase ref in loadtest guard; storage transforms disabled; AI chat route disabled |
| **Modeled estimates** | All **$** costs; DAU/MAU ratios; peak concurrent; capacity “Yes/Marginal/No” at 10k/100k |
| **Unknown without prod access** | Current Supabase **plan tier**, compute size, Realtime limits in contract, actual MAU, pool wait, pg_stat hotspots, egress TB/mo |

---

## Appendix A — Key file index

| Area | Path |
|------|------|
| Web performance audit (Aug 2026) | [WEB_SUPABASE_PERFORMANCE_AUDIT.md](../WEB_SUPABASE_PERFORMANCE_AUDIT.md) |
| Backend V2 index | [docs/backend-v2/README.md](./backend-v2/README.md) |
| Broker worker | [docs/tradovate/BROKER_SYNC_WORKER.md](./tradovate/BROKER_SYNC_WORKER.md), `services/tradovate-sync-worker/run.ts` |
| Vercel crons | `vercel.json` |
| Feature flags | `lib/backendV2/flags.ts` |
| Trade owner read | `lib/tradeOwnerRead.ts`, `lib/appDataCache.ts` |
| Realtime (web policy) | `lib/realtimePublicationPolicy.ts` |
| Realtime (iOS) | `native-ios/TradeTraxs/TradeTraxs/Data/Realtime/RealtimeArchitecture.swift`, `SupabaseProviders.swift` |
| Load test | `loadtest/README.md`, `loadtest/phase-a-read.js` |
| Notifications | `lib/server/notifications/NotificationService.ts` |
| Push | `lib/server/push/apns.ts`, `app/api/push/register/route.ts` |
| Leaderboard API | `app/api/leaderboard/trades/route.ts` |
| Community unread | `lib/communityRoomUnread.ts` |

---

## 13. Failure recovery and system resilience

**Audit mode:** Read-only code/migration review. No chaos testing, failover drills, or production log analysis. Findings are labeled **Confirmed** (evidence in repo), **Theoretical** (requires live failure injection), or **Unknown** (not documented in repo).

### 13.1 Supabase outages (PostgreSQL, Auth, Storage, Realtime)

| Component | Web behavior | iOS behavior | Data loss / duplication |
|-----------|--------------|--------------|-------------------------|
| **PostgreSQL / PostgREST down** | Cached trades/accounts in module `appDataCache`; profile in `settingsProfileCache` / `userBootstrapCache` (sessionStorage). Failed fetch **does not cache empty history** — keeps prior rows, sets `invalidated`, **one retry after 4s** (`lib/appDataCache.ts`). User-facing copy via `lib/userFacingError.ts` (`NETWORK_ERROR`). | Disk-first patterns (feed, profile, GRDB analytics shadow); `UserFacingError` offline title; `ExperienceFeedbackViews` offline banner with Retry. | **Theoretical:** optimistic writes (likes, messages) may **rollback** on failure (`lib/optimisticMutation.ts`). **Confirmed:** failed trade load does not wipe cache as empty. |
| **Auth down** | JWT refresh handled by Supabase client; session expiry surfaces as `SESSION_EXPIRED` on BFF calls (`lib/startTraxProCheckout.ts`). | Same shared Auth; settings export shows re-auth message. | Users cannot **mutate** server state without auth; read of local cache may still work on iOS. |
| **Storage down** | Uploads fail at XHR (`lib/supabaseStorageUploadWithProgress.ts`); no global outbox on web found in audit. | `GlobalUploadCoordinator` — failed jobs stay **`.failed`** with **checkpoint retry** maps per kind (`GlobalUploadCoordinator.swift`). | **Theoretical:** partial upload then DB insert failure could orphan storage objects (not verified). |
| **Realtime down** | Channels error silently until remount; notifications may stale until Navbar refetch. | `LiveSupabaseRealtimeProvider` reconnect + **`SupabaseReconnectRepairCoordinator`** → `SocialRealtimeReconciliationCoordinator` bounded repair; Messaging/Activity **reconnect catch-up** (`MessagingDomain`, `ActivityInboxStore`). | **Theoretical:** missed events until repair/bootstrap; **dedupe** on messages (`lib/optimisticMessage.ts`, iOS merge tests). |

**Can users view existing trades/analytics offline?**

- **Web — Confirmed partial:** In-memory `getCachedTrades` / dashboard **`analyticsHistory`** cache serves last successful fetch; no durable full-history offline DB on web.
- **iOS — Confirmed partial:** GRDB shadow for analytics (Release GRDB-first flags **OFF** by default per `Data/Analytics/Local/README.md`); vault/social disk caches per architecture doc.

**Safe retry on reconnect?**

- **Reads:** `withTransientPostgrestRetry` — max **2 attempts** for transient schema-cache errors (`lib/postgrestTransientRetry.ts`); profile bootstrap uses it.
- **Writes:** Generally **no automatic retry** on web; iOS `NetworkClient` retries **idempotent GET/HEAD only** (`RetryPolicy.idempotentReads`, max 3 attempts).

---

### 13.2 Broker sync failures (Tradovate, Rithmic)

| Question | Finding | Evidence |
|----------|---------|----------|
| Disconnect mid-sync? | Sync status → `syncing` with **120s lock**; release sets `success`, **`partial`**, or `error` (`lib/integrations/brokerIntegrationSync.ts`, `syncTradovateBrokerAccount.ts`). | `SYNC_LOCK_MS = 120_000`, `BROKER_ACCOUNT_SYNC_STATUSES` includes `partial`. |
| Duplicate trades? | **Confirmed mitigations:** unique `(user_id, broker_lifecycle_id)`; unique broker executions per fill; upsert by lifecycle in `persistBrokerTrades.ts`; extensive idempotency tests (`tradovateSep2026E2ERegression.test.ts`, `tradovateResyncRegression.test.ts`). | `20260914260000_broker_integration_executions_sync.sql` |
| Missing trades? | **Confirmed risk:** `partial` / `IMPORT_SUCCESS_PARTIAL` when acquisition incomplete; user sees error codes on mapping (`import_partial`, provider failures). | `tradovateSyncCompleteness.ts`, `tradovateClientSyncOutcome.ts` |
| Cursors / checkpoints | `max_external_fill_id`, `max_executed_at`, `provider_sync_state` updated on **`releaseBrokerSyncLock`**; coalescer runs **one follow-up** after in-flight sync (`tradovateSyncCoalesce.ts`). DB column `pending_sync_after_current` exists but worker coalescer uses in-memory `pendingAfterSync` — **cross-process** follow-up relies on lock release + new events. | `brokerIntegrationSync.ts`, migration `20260914270000_broker_auto_sync.sql` |
| Token expiry | Worker refreshes tokens; **`reconnect_required`** on refresh failure (`tradovateConnectionAutoSync.ts`, `markBrokerConnectionReconnectRequired`). | Settings UI via `tradovateListenerUiState` |
| User visibility | **Confirmed:** `last_sync_status`, `last_sync_error_code`, listener labels (**Worker offline** if heartbeat &gt; 90s). | `BrokerImportActionAvailability.swift`, `tradovateListenerStatus.ts` |
| Tradovate auto-sync | **Confirmed:** Without worker, auto-sync **does not run**; manual sync still works (`docs/tradovate/BROKER_SYNC_WORKER.md`). | |
| Rithmic | Serverless **120s** cap; disconnect mid-import → **Theoretical** partial state; same sync status table pattern when wired through shared broker helpers. | `app/api/integrations/rithmic/**/route.ts` `maxDuration` |

**Recovery:** Worker **reconnects WebSocket** with backoff (`TradovateConnectionAutoSyncSession`); **startup/reconnect full reconciliation** documented in broker worker doc. **Manual:** user **Reconnect OAuth** (iOS `BrokerImportProgressView` → `.reconnect` for Tradovate).

---

### 13.3 Stripe and billing failures

| Scenario | Behavior | Automatic recovery? | Risk |
|----------|----------|---------------------|------|
| Checkout succeeds, webhook delayed | Client sets **`markStripeReconciliationPending`**; **`syncMembershipAfterStripeCheckout`** polls profile up to **10 × 800ms** (`lib/syncMembershipAfterStripeCheckout.ts`, `lib/stripeReconciliation.ts`). | **Partial auto** (≤ ~8s poll) | User may see non-Pro briefly; then Pro if webhook lands. |
| Checkout succeeds, webhook **never** applies | Poll exhausts → `reconciled: false`. User paid in Stripe but profile may stay non-Pro until manual support / Stripe dashboard / re-fetch subscription event. | **Manual** | **Confirmed gap** unless user hits entitlement API refresh path. |
| Webhook handler throws internally | Outer handler often **logs and still returns `200 OK`** (`app/api/stripe/webhook/route.ts` end); Stripe **will not retry** those failures. | **No** | **Confirmed defect class** for entitlement + affiliate side effects. |
| Duplicate webhooks | Affiliate **`referrals.stripe_invoice_id`** duplicate check before insert (`invoice.paid` handler). Subscription sync is **upsert-by-customer** profile update — duplicate events mostly **idempotent**. | **Mostly auto** | **Theoretical:** double `referral_earnings` if duplicate check races before unique index (DB unique index assumed — `referrals_stripe_invoice_id_uidx` per test comment). |
| `customer.subscription.updated` / `deleted` | Syncs `subscription_status`, `is_pro` via `buildSubscriptionProfileUpdatePayload` / `SUBSCRIPTION_INACTIVE`. | **Auto** on event delivery | **Theoretical:** `past_due` may not revoke Pro immediately — depends on Stripe status mapping (`is_pro: active \|\| trialing` only in checkout payload builder; updated handler uses full status). |
| `invoice.payment_failed` | **Not handled** in webhook switch (grep). | **Unknown / likely none in-app** | **Theoretical:** dunning relies on Stripe + later `subscription.updated`. |
| Apple `billing_retry` / grace | Treated as **live access** on client (`lib/billingEntitlement.ts` `APPLE_LIVE_STATUSES`). | StoreKit + `/api/apple/subscription/sync` | **Confirmed** intentional grace behavior. |
| Entitlement source of truth | **`/api/billing/entitlement`** snapshot; profile `is_pro` not sole gate (`lib/billingEntitlement.ts` comment). | Refetch on demand | Reduces false lockout if profile stale but entitlement row correct — **requires live test**. |

---

### 13.4 Network interruptions (iOS-focused; web gaps)

| Operation | iOS | Duplication on retry | Empty vs offline |
|-----------|-----|----------------------|------------------|
| Media upload (reel/post/story/trade) | `GlobalUploadCoordinator` checkpoints + explicit **retry**; terminal job IDs prevent double complete. | **Theoretical:** retry after partial DB write — mitigated by publish IDs / specs (needs live test). | Failed phase → `.failed` + retry UI |
| DM send | Failed send state + retry in bubble menu; optimistic merge by content/time (`optimisticMessage.ts`). | Realtime dedupe by message `id` | `send_status: failed` |
| Broker import | Progress UI + reconnect path | Lifecycle unique index | Status labels from sync row |
| Expenses / income | **Assumed** standard Supabase insert from clients (no global outbox found) | **Theoretical** double-submit if user taps save twice | **Unknown** — likely error toast only |

**Web:** No first-class offline mode; **`navigator.onLine`** not used broadly (grep). Users see generic network errors; cached data may still render while mutations fail.

---

### 13.5 Database and financial integrity

| Operation | Transaction boundary | Idempotency | Partial failure risk |
|-----------|---------------------|-------------|----------------------|
| **Prop payout delete + balance restore** | Single PL/pgSQL function `delete_prop_payout` — **atomic statement block** (implicit transaction). | Re-run raises **Payout not found** if already deleted. | **Low** if function completes; **Theoretical** if caller retries mid-flight (blocked by `for update`). |
| **Broker trade persist** | Per-lifecycle loop — **not one DB transaction** across all lifecycles. | Lifecycle + fill uniqueness | **Confirmed:** mid-batch crash could leave **subset** imported; status should reflect `partial`. |
| **Broker sync lock** | Compare-and-set via `sync_lock_until` | Second worker gets `false` from `tryAcquireBrokerSyncLock` | **Theoretical:** two workers without DB lock discipline could race — doc says scale worker to **1**. |
| **Affiliate commission** | Referral insert + profile earnings update — **two steps** in webhook | Invoice id dedupe | **Theoretical:** insert succeeds, earnings update fails → logged, **200 OK** |
| **Trade delete** | Cascade migrations exist (`20260620140000_trade_delete_cascade.sql` — cited in prior audit) | — | **Theoretical** orphan media in Storage |
| **Achievements / payouts** | Achievement rows tied to payout cycles; deleted in `delete_prop_payout` | — | **Theoretical** fuzzy achievement match fallback in delete function (date/amount heuristic) |
| **Optimistic likes** | Client rollback; **23505 unique** → success (`optimisticMutation.ts`) | **Confirmed** idempotent like |

**Expenses / income (20261024 migrations):** Row-level inserts with CHECK constraints; **no multi-table RPC** seen for single expense+ledger — **Theoretical** inconsistency if client performs multi-step sequences without server RPC.

---

### 13.6 Recovery, monitoring, and single points of failure

| Mechanism | Present? | Evidence |
|-----------|----------|----------|
| Exponential backoff (Realtime) | **Yes (iOS)** | `ReconnectPolicy` in `RealtimeArchitecture.swift`; Tradovate worker reconnect |
| Exponential backoff (HTTP) | **iOS reads only** | `RetryPolicy` + `ExponentialBackoffStrategy` |
| Circuit breakers | **No** | Repo grep — none |
| Error reporting | **Sentry** on web (`@sentry/nextjs`); iOS architecture mentions Crashlytics/Sentry choice | Not unified in audit |
| Structured broker logs | **Yes** | `logTradovateSync`, JSON stdout in worker doc |
| Stripe webhook logging | Verbose `devLog` / console; affiliate temp logs | Production diagnosability **medium** |
| Backup / PITR runbook | **Not in repo** | **Unknown** — assume Supabase dashboard feature, not verified |
| Single points of failure | **Tradovate sync worker (1 instance)**; **Vercel region**; **single Supabase project**; leaderboard cache build | `BROKER_SYNC_WORKER.md` |

**Alerts gap (Theoretical):** No code references to PagerDuty/Opsgenie; reliance on Vercel/Supabase/Sentry dashboards **assumed**.

---

### 13.7 Top 10 failure scenarios (by severity)

| Rank | Scenario | User experience | Recovery | Data risk | Primary code / config |
|------|----------|-----------------|----------|-----------|------------------------|
| 1 | **Supabase Postgres hard down** | Web/iOS: cached reads may work briefly; writes fail; spinners/errors | Auto retry limited (reads); manual wait | No duplicate; **stale UI** | `appDataCache.ts`, iOS caches |
| 2 | **Stripe webhook 200 on handler failure** | Paid but not Pro; affiliate commission missing | **Manual** replay from Stripe CLI/dashboard | **Missing entitlement** | `app/api/stripe/webhook/route.ts` |
| 3 | **Tradovate worker offline** | Auto-sync stops; “Worker offline” | Deploy worker | **Missing new trades** until manual sync | `tradovate-sync-worker`, heartbeat |
| 4 | **Broker sync partial acquisition** | Some trades imported; `partial` status | User retry sync | **Missing trades**, not duplicates | `syncTradovateBrokerAccount.ts` |
| 5 | **Realtime partition (long)** | Stale feeds/inbox until reconnect repair | iOS auto repair; web partial | **Missed messages** until reconcile | `SupabaseReconnectRepairCoordinator.swift`, web channel remount |
| 6 | **iOS upload interrupted** | Failed bar + Retry | User retry from checkpoint | **Theoretical** duplicate post if retry bug | `GlobalUploadCoordinator.swift` |
| 7 | **OAuth token expired (Tradovate)** | Reconnect required label | User reconnect settings | Sync paused | `markBrokerConnectionReconnectRequired` |
| 8 | **Rithmic import &gt; 120s on Vercel** | Import fails timeout | User retry | **Partial** sync state possible | Rithmic API routes `maxDuration` |
| 9 | **Affiliate webhook partial write** | User Pro OK; referrer unpaid | **Manual** reconciliation | **Missing commission** | `invoice.paid` handler |
| 10 | **Web cold cache miss during outage** | Empty dashboard though user has trades | Retry on reconnect | **False empty** mitigated for trades cache | `appDataCache.ts` invalidation rules |

---

### 13.8 Recommended fixes (resilience), ranked by impact

| Rank | Fix | Impact | Effort | Type |
|------|-----|--------|--------|------|
| 1 | Return **5xx** from Stripe webhook when profile/entitlement update fails (allow Stripe retry) + idempotent handlers | High | Medium | **Confirmed need** |
| 2 | Post-checkout **entitlement poll** via `/api/billing/entitlement` (not only `profiles.is_pro`) until active or timeout + support UX | High | Low | Enhancement |
| 3 | Document/runbook **Supabase PITR + restore**; test quarterly | High | Low ops | **Unknown baseline** |
| 4 | Web **Global upload outbox** or reuse iOS checkpoint pattern for reels/posts | Medium | High | Gap vs iOS |
| 5 | Multiplex web Realtime + **reconnect reconcile** (parity with iOS) | Medium | Medium | From §5 scalability + resilience |
| 6 | Handle **`invoice.payment_failed`** / `past_due` explicitly in webhook | Medium | Low | **Theoretical** |
| 7 | Broker: **distributed lock** before multi worker | Medium | High | Scale path |
| 8 | Wrap affiliate insert + earnings in **DB transaction RPC** | Medium | Medium | Integrity |
| 9 | Alerting: Sentry issues + Supabase health + worker heartbeat stale | Medium | Low | Ops |
| 10 | Web offline **empty vs error** states on `useCachedTrades` (`invalidated` flag surfaced in UI) | Low–Med | Low | UX |

---

## 14. System resilience assessment (Web vs iOS)

| Dimension | Web | iOS |
|-----------|-----|-----|
| **Offline read** | Moderate — session/module caches only | Stronger — disk caches + GRDB shadow path |
| **Offline write** | Weak — no outbox | Moderate — upload coordinator + message retry |
| **Reconnect** | Ad hoc (cache retry, Realtime remount) | Strong — RealtimeHub, repair coordinators, inbox catch-up |
| **Billing recovery** | Stripe reconciliation polling | StoreKit + server entitlement sync |
| **Broker recovery** | Same API; worker dependency | Same + native reconnect UX |
| **Financial integrity** | Client-driven multi-step | Same backend; fewer raw fan-out paths on native |
| **Observability** | Sentry + console | Sentry/Crashlytics (per architecture); pressure logs |

**Overall:** iOS is **architecturally ahead** on resilience for uploads, Realtime, and offline messaging. Web depends on **Supabase availability** and **correct webhook side effects** for money paths. Both share the same **Postgres integrity model** for broker idempotency and payout RPCs.

---

## Appendix B — Resilience evidence index

| Topic | Path |
|-------|------|
| Trade cache failure behavior | `lib/appDataCache.ts` |
| PostgREST transient retry | `lib/postgrestTransientRetry.ts` |
| Stripe reconciliation poll | `lib/syncMembershipAfterStripeCheckout.ts`, `lib/stripeReconciliation.ts` |
| Stripe webhook | `app/api/stripe/webhook/route.ts` |
| Billing entitlement | `lib/billingEntitlement.ts`, `app/api/billing/entitlement/route.ts` |
| Broker lock + status | `lib/integrations/brokerIntegrationSync.ts` |
| Broker persist idempotency | `lib/integrations/tradovate/persistBrokerTrades.ts`, broker migrations |
| Tradovate coalesce / worker | `lib/integrations/tradovate/tradovateSyncCoalesce.ts`, `docs/tradovate/BROKER_SYNC_WORKER.md` |
| Optimistic mutations | `lib/optimisticMutation.ts`, `lib/optimisticMessage.ts` |
| iOS upload recovery | `native-ios/.../GlobalUpload/GlobalUploadCoordinator.swift` |
| iOS Realtime repair | `SupabaseReconnectRepairCoordinator.swift`, `SupabaseProviders.swift` |
| iOS network retry | `Platform/Networking/Retry/RetryPolicy.swift`, `NetworkClient.swift` |
| Prop payout delete RPC | `supabase/migrations/20261024043000_delete_prop_payout_restore_balance.sql` |
| User-facing errors | `lib/userFacingError.ts`, `UserFacingError.swift` |

---

*End of report.*
