> **Note (Aug 2026):** This is a **static read-only audit** from migration history and query shapes. Runtime network capture and pool-wait metrics were **not measured** here. Several findings have since been addressed in Backend V2 phases (session/feed/profile/messaging/room bootstraps, community event-driven unread, Reel idle poster fix). See [docs/backend-v2/README.md](./docs/backend-v2/README.md) for current implementation status vs. measured validation.

# TradeTraxs Web App + Supabase Performance Audit

**Date:** 2026-08-17  
**Scope:** Web app only (`app/`, `lib/`, `middleware.ts`, `supabase/migrations` as evidence).  
**Excluded:** `native-ios/`, Capacitor/native implementation changes.  
**Mode:** READ-ONLY diagnosis. No code, schema, RLS, index, function, trigger, or config changes. No migrations. No deploys. No production `EXPLAIN ANALYZE`. No unbounded table scans.

---

## 1. Executive summary

The web product is an **App Router (Next.js 16.2.3) shell with almost entirely client-side Supabase access**. There is no React Query/SWR. Freshness relies on module caches, sessionStorage route caches, deferred auth warm, and many Realtime channels.

**Why the app feels slow (ranked):**

1. **Cold bootstrap fans out ~15–22 REST/RPC calls** (profile + deferred trades/accounts warm + Getting Started checklist + Navbar badges) before or alongside page data.
2. **Dashboard / Trades / Calendar request unbounded full trade history** after the 120-row window (`ensureFullTradesHistory`) — high payload and Disk IO for power users.
3. **Feed opens ~7–12 queries plus up to 5 Realtime channels** (4 content streams + reel likes), with a following-ids → merge → engagement waterfall.
4. **Community rooms poll presence (~2 writes/reads per minute) and unread (60s)** while a room is open — continuous idle load.
5. **Very large Client Components** (community ~5.2k LOC, profile ~4.2k, messages thread ~3.6k, feed ~3.0k) mean heavy JS parse/hydrate on navigation even when caches hit.

**Database live stats were not collected:** Supabase MCP was not available in this environment; no direct Postgres URL; Supabase CLI not installed. Index/RLS findings below are from **migration history + query shapes** (static). Runtime network capture was **not** run against production to avoid load.

---

## 2. Current data-loading architecture

| Layer | Detail |
|-------|--------|
| Next.js | `16.2.3`, React `19.2.4`, **App Router only** |
| Middleware | Host/HTTPS/security headers only — **no Supabase session refresh** (`middleware.ts`) |
| Browser client | `lib/supabaseClient.ts` — module singleton `createClient(anon)` — **dominates product UI** |
| Duplicate client | `lib/supabase.ts` — same pattern; used by `app/backtest/page.tsx` only |
| SSR cookie client | `lib/supabaseServer.ts` — **defined but unused** by product pages |
| Admin / service | `lib/supabaseAdmin.ts`, `lib/supabaseServiceRole.ts`, `app/api/_lib/getRouteUser.ts` |
| Cache library | **Custom** — `appDataCache`, many `*SessionCache` modules, settings/bootstrap caches. **No React Query / SWR** |
| Auth/profile | `lib/UserProfileProvider.tsx` (global) |
| Checklist | `lib/GettingStartedProgressProvider.tsx` |
| Prefetch | `lib/dataPrefetch.ts` → `warmAppDataCaches` (deferred 1s) |
| Realtime managers | Shared: `lib/notificationRealtime.ts`. Per-page channels elsewhere. No `RealtimeHub` class |

**Rendering model:** Root `app/layout.tsx` mounts global providers + gate shells + `AppChrome` (Navbar). Product pages are overwhelmingly `"use client"` and talk to PostgREST from the browser. Marketing uses `revalidate = 86400`. Product data does **not** use `revalidatePath` / `revalidateTag`.

**Architecture diagram:**

```
Browser
  └─ UserProfileProvider (onAuthStateChange INITIAL_SESSION|SIGNED_IN)
       ├─ fetchSettingsProfileRow → profiles
       ├─ warmAppDataCaches (deferred)
       │    ├─ trades limit 120 + accounts
       │    └─ settings / notification prefs / achievements
       ├─ profiles realtime UPDATE
       └─ GettingStartedProgressProvider → checklist counts
  └─ FreePlanAccountSlotShell → ensureAccounts + ensureTrades (free tier)
  └─ Navbar → notification count + DM unread RPC chain + shared notif channel
  └─ Page (client) → own queries / session caches / page realtime
```

---

## 3. Exact app-bootstrap request flow

Ordered trace for a **cold signed-in visit** (no sessionStorage / module cache):

```
T0  Document + JS hydrate (large client bundles)
T1  supabase.auth.onAuthStateChange → INITIAL_SESSION
T2  applyAuthSession
    a. Optional instant paint from settingsProfileCache / userBootstrapCache
    b. warmAppDataCaches scheduled (+~1000ms) unless Stripe reconcile pending
    c. fetchSettingsProfileRow (profiles SELECT, wide USER_PROFILE_SELECT / APP_PROFILE_SELECT)
    d. If missing: ensureProfileForUser (+ possible force refetch)
    e. setLoading(false)
    f. runDeferredBootstrap → optional beta referral repair → subscribe profiles realtime
T3  GettingStartedProgressProvider (user ready)
    → fetchGettingStartedChecklistSignals
       parallel: profile flags (skipped if preloaded), trade counts if cache miss,
       profile_posts count, followers count, room_members(+rooms), public/private trade probes
T4  FreePlanAccountSlotShell (non-Pro)
    → Promise.all(ensureAccountsLoaded, ensureTradesLoaded)  // may join warm in-flight
T5  Navbar (deferred after !loading)
    → notifications head count
    → fetchTotalUnreadMessageCount:
         conversation_participants + hidden/blocked RPC
         → muted prefs
         → get_conversation_unread_counts RPC
    → subscribeNotificationChanges (shared channel)
T6  warmAppDataCaches fires
    → trades .limit(120) + accounts
    → nested: trading account settings, notification prefs, achievements
T7  Route page mounts and adds its own waterfall (dashboard full history, feed, etc.)
```

**Auth events that re-run bootstrap:** `INITIAL_SESSION`, `SIGNED_IN` only (`AUTH_SYNC_EVENTS`). Token refresh does **not** re-fetch profile. Same-user `SIGNED_IN` with existing profile is skipped (tab-focus recovery). **Confirmed.**

**Waterfall characterization:** Profile is sequential before deferred realtime; warm is parallel trades+accounts then nested settings; Getting Started and Navbar are parallel to each other but **additive** to page load. Free-plan users can race the same `ensure*` path as warm (**Medium** duplicate risk).

---

## 4. Page-by-page request inventory

Estimates are **Supabase REST/RPC round-trips** for a typical signed-in user. Shell overhead (**~15–22 cold**, **~0–6 residual** when auth already resolved) applies on top unless noted.

| Page | Cold (auth resolved) | Return (&lt;5m warm) | Waterfall | Realtime | Notes |
|------|----------------------|---------------------|-----------|----------|-------|
| **Dashboard** | 2–4 | 0–2 | recent trades → full history | shell | `useCachedTrades({ fullHistory: true })` |
| **Feed** | 7–12 | 0 (+ channels) | following → 4 batches → engagement | up to 5+ | page size 8; merge top-up possible |
| **Explore** | ~6 | 0 | profiles → social/posts; trade meta +1s | shell | posts capped 500/batch |
| **Trades** | 2–3 | 0–1 | same full history + reels | shell | |
| **Calendar** | 2–3 | 0–1 | same as trades | shell | |
| **Profile (own)** | 6–12 | 0–2 | profile → follow → sequential prefetch | reel likes | analytics unbounded trades; wall `select("*")` |
| **Profile (other)** | +3 follow snapshot | 0–2 | same | reel likes | |
| **Messages inbox** | ~5 | 0 | membership → conversations → unread | shell | duplicates Navbar unread |
| **DM thread** | 6–10 | 0–2 | access → messages page | 1 messages channel | share picker unbounded trades |
| **Community** | 6–8 then +2/min | 0–2 + presence | rooms → sections → messages | room + typing | unread poll 60s |
| **Notifications** | 2 | 0–1 | list + sender profiles | shared notif | limit 200 |
| **Settings** | 0–1 | 0 | cache from bootstrap | profile channel | affiliate tab +2 |
| **Leaderboard** | 2 browser (+ N server RPC pages) | 0–1 | API then profiles.in | shell | API may page all public trades |
| **QuickTradeModal** | 2–4 on open | same | accounts `*` + profile + copy groups | — | bypasses appDataCache |
| **Create post** | 1+ storage + full wall reload | — | insert → `select("*")` all posts | — | |

---

## 5. Realtime subscription inventory

| Channel pattern | Created in | Tables / events | Filter | Start / stop | Incremental? | Duplicate risk |
|-----------------|------------|-----------------|--------|--------------|--------------|----------------|
| `notif-shared-{userId}` | `lib/notificationRealtime.ts` | `notifications` `*` | `user_id=eq` | First subscriber; removed when last unsubscribes | Listener-driven (Navbar refetches **count**) | **Low** — intentionally shared |
| `profile:{userId}:{useId}` | `UserProfileProvider.subscribeProfileRealtime` | `profiles` UPDATE | `id=eq` | After bootstrap; cleanup on unmount/sign-out | Applies `payload.new` | **Low** (unique suffix per provider mount) |
| `feed-trade-posts-{userId}` | `app/(app)/feed/page.tsx` | `posts` INSERT | scope-dependent | Feed mount / cleanup | Incremental insert + engagement hydrate | Medium if remount races |
| `feed-profile-posts-{userId}` | feed | `profile_posts` INSERT | | | Incremental | Medium |
| `feed-achievement-posts-{userId}` | feed | `achievement_posts` INSERT | | | Incremental | Medium |
| `feed-reels-{userId}` | feed | `reels` INSERT | | | Incremental | Medium |
| `feed-reel-likes-{userId}` | feed | `reel_likes` `*` | `in.(reelIds)` | | Patches like map | Medium — filter grows with visible reels |
| `active-stories:{userIdsKey}` | `lib/useActiveStories.ts` | `stories` `*` | per users | Stories hook | Refresh path | Medium if key churn |
| `messages-{conversationId}` (+ broadcast) | `app/messages/[id]/page.tsx` | `messages` `*` | conversation | Thread mount | Incremental / optimistic dedupe | Low |
| `room-{roomId}` | `app/community/page.tsx` | `room_messages` INSERT; reactions `*` | room | Selected room | Hydrate fetch on INSERT | Low–Med |
| `typing-room-{roomId}` | community | broadcast typing | | | | Low |
| `profile-reel-likes-{profileId}` | `app/profile/[id]/page.tsx` | `reel_likes` | | Reels loaded | Patch | Low |
| `trade-{id}-{random}` | `TradeSocialLayer.tsx` | `trade_likes` `*`; `trade_comments` INSERT/UPDATE | trade_id | Per mounted social layer | **Like events refetch all like rows** | **High** if many cards mount |
| `comment-likes-…` | `lib/useCommentLikes.ts` | `comment_likes` | in-filter | Comments UI | | Med |

**Preferred architecture violations:**

- Feed: many channels vs one multiplexed hub.
- `TradeSocialLayer`: Realtime event → **full likes list refetch** (not row-delta).
- Community: Realtime **plus** presence heartbeat writes **plus** 60s unread polling.
- Navbar: Realtime notification event → **head count refetch** (acceptable but adds REST chatter).

---

## 6. Duplicate-query findings

| # | Severity | Confidence | Pattern | Evidence | Recommended correction |
|---|----------|------------|---------|----------|------------------------|
| D1 | **High** | Confirmed | Auth warm + FreePlan shell + dashboard/trades all call `ensureTradesLoaded` / `ensureAccountsLoaded` | `dataPrefetch.ts`, `FreePlanAccountSlotShell.tsx:113`, dashboard/trades hooks | Single bootstrap owner; FreePlan subscribe to cache only |
| D2 | **High** | Confirmed | Navbar DM unread vs Messages inbox unread | `Navbar` → `fetchTotalUnreadMessageCount`; messages page parallel unread | Share unread module cache / one session store |
| D3 | **Medium** | Confirmed | QuickTradeModal re-fetches `accounts.select("*")` + profile despite provider/cache | `QuickTradeModal.tsx:297+` | Use `ACCOUNTS_SELECT` + `getCachedAccounts` / profile context |
| D4 | **Medium** | Confirmed | Getting Started may query trade counts while warm still loading | `gettingStartedChecklistSignals.ts` | Wait for trades cache or use head counts only after warm |
| D5 | **Medium** | Confirmed | Own profile analytics/trades ignore `appDataCache` | `profile/[id]/page.tsx` separate public-trade queries | Reuse owner cache or shared RPC aggregates |
| D6 | **Low** | Confirmed | Duplicate anon clients | `supabaseClient.ts` vs `supabase.ts` | Delete unused / consolidate |
| D7 | **Medium** | Strong | Notification count (Navbar) + notifications page list | Same table, different shapes | Derive badge from list cache when on inbox; else keep count |

**Duplicate-query pattern count (distinct):** **7** confirmed/strong above (plus engagement fallback 8-select path as conditional duplicate of RPC).

---

## 7. Request-waterfall findings

| # | Severity | Confidence | Waterfall | Why expensive | Fix |
|---|----------|------------|-----------|---------------|-----|
| W1 | **Critical** | Confirmed | user → profile → (gates) → page | Blocks usable chrome until profile resolves when cache cold | Keep instant cache paint (already partial); never block Navbar badges on full profile width |
| W2 | **High** | Confirmed | trades limit 120 → **full history** | Second large query on dash/trades/calendar | Metrics via SQL aggregates / dated windows; don’t ship all rows |
| W3 | **High** | Confirmed | followingIds → 4 feed batches → engagement RPC | Serial barrier before cards have counts | Parallel following with cached following; engagement in same RPC as feed page |
| W4 | **High** | Confirmed | Profile sequential prefetch order | Posts→reels→analytics→… delays tabs | Parallelize independent tabs; defer analytics |
| W5 | **Medium** | Confirmed | Messages: participants → conversations → unread | Extra RTT | Single inbox RPC |
| W6 | **Medium** | Confirmed | Copy trading groups → members | Extra RTT on Pro dash | Join in one query |
| W7 | **Medium** | Confirmed | Navbar unread: participants → muted → RPC | 3+ hops every badge refresh | One `get_navbar_badges` RPC |

---

## 8. Over-fetching and pagination findings

| # | Sev | Conf | File / function | Behavior | Why expensive | Fix |
|---|-----|------|-----------------|----------|---------------|-----|
| O1 | **Critical** | Confirmed | `appDataCache.ensureFullTradesHistory` | All user trades, `TRADES_APP_SELECT` (~40+ cols), no limit | Large JSON + RLS + index scan per user | Server aggregates / keyset pages / column subsets per screen |
| O2 | **High** | Confirmed | `profile/[id]` analytics / summary trades | Unbounded public trades | Same | Aggregate RPC |
| O3 | **High** | Confirmed | `profile` wall `select("*")` (+ after create) | All `profile_posts` | Over-fetch + reload | Limit/range; prepend on create |
| O4 | **High** | Confirmed | `messages/[id]` trade share picker `select("*")` | All trades | Opens with full journal | Search RPC / recent window |
| O5 | **High** | Confirmed | `api/leaderboard/trades` while-loop pages of 1000 | May load **all** public trades server-side | CPU + transfer; cached 60s | Precomputed leaderboard table / capped window |
| O6 | **Medium** | Confirmed | `fetchFollowingIds` / explore follow graph | Unbounded following edges | Grows with graph | Cap / keyset |
| O7 | **Medium** | Confirmed | `QuickTradeModal` / modals `accounts.select("*")` | All account columns | Bypass lean `ACCOUNTS_SELECT` | Reuse cache |
| O8 | **Medium** | Confirmed | `TradeSocialLayer` loads all `trade_likes` for count | Count via row download | Use `count: exact, head` or denormalized count |
| O9 | **Medium** | Confirmed | Explore `profile_posts` `.limit(500)` | Heavy batch | Lower cap / aggregate |
| O10 | **Medium** | Strong | Feed engagement fallback | 8 unbounded-in-id selects of like/comment **rows** | If RPC missing | Ensure RPC always; never fall back in prod |
| O11 | **Low** | Confirmed | Navbar `select("*", { count, head })` | Count-only | Harmless-ish but noisy | `select("id", { count, head })` |
| O12 | **Medium** | Confirmed | Getting Started `room_members` + nested rooms | Membership list for boolean | Over-fetch | `exists` / head count |

**Unbounded queries (confirmed hot path):** ≥ **8** (full trades, profile analytics trades, wall posts, DM trade picker, following ids, accounts in modals, leaderboard full scan, TradeSocial likes list).  
**Suspected N+1 patterns:** ≥ **5** (TradeSocial like refetch; feed engagement fallback; copy-group members; per-card social layers; optional comment-like channels).

---

## 9. Database findings

### Status of live diagnostics

| Tool | Result |
|------|--------|
| Supabase MCP (`get_advisors`, `execute_sql`, …) | **Not available** in this agent session |
| Supabase CLI | **Not installed** |
| Direct `DATABASE_URL` / Postgres | **Not present** in `.env.local` (URL + anon + service role only) |
| `pg_stat_statements` / `EXPLAIN` | **Not run** (would require production DB access; avoided per load rules) |

**No production SQL was executed.**

### Static evidence from migrations (useful, not measured)

**Indexes already added for hot paths** (good signals prior work happened):

- `trades_user_id_created_at_idx`, public/mode composites (`20260703160000`, `20260703170000`)
- Messaging cursor indexes (`20260718090000_phase1_messaging_scalability.sql`)
- Notifications unread + inbox (`notifications_user_id_unread_idx`, `notifications_user_id_created_at_idx`)
- Feed/posts/comments/followers (`20260804230000_phase3_hot_path_indexes.sql`)
- Engagement tables for profile posts, reels, achievements, trade likes/comments

**Likely remaining DB risks (Suspected until pg_stat confirms):**

1. **Full-history trades select** still dominates IO even with `(user_id, created_at)` index — because it returns **all rows**.
2. **Leaderboard** paging public trades — index helps order, not result size.
3. **`room_presence` upsert + select every 60s** — write amplification; check index on `(room_id, last_seen)`.
4. **Follow-graph / feed `not.in.(following)`** can degrade with large following sets.
5. **Unused / overlapping indexes** — cannot confirm without `pg_stat_user_indexes`.

### Hottest client tables by `.from("…")` call-site frequency

`profiles` (74), `trades` (41), `reels` (29), `accounts` (26), `room_members`/`messages` (~18), `posts`/`profile_posts`/`followers` (~16–17), …

---

## 10. RLS / function / trigger findings

| # | Sev | Conf | Finding | Evidence | Recommendation |
|---|-----|------|---------|----------|----------------|
| R1 | **High** | Strong | Policies use bare `auth.uid()` extensively; **zero** `(select auth.uid())` scalar subquery wrappers found in migrations | 534 `auth.uid()` refs; grep found no `(select auth.uid())` | Rewrite hot SELECT policies to `(select auth.uid())` to avoid per-row initplan re-eval |
| R2 | **High** | Confirmed | `profile_posts` / `stories` SELECT policy does owner OR public-profile EXISTS OR followers EXISTS | `20260609190000_profile_posts_stories_secure_rls.sql` | Ensure supporting indexes; consider security-barrier view / helper marked stable |
| R3 | **Medium** | Strong | Room policies call `is_active_room_member` / `is_room_owner` helpers (65 migration refs) | Room RLS migrations | Confirm helpers are `STABLE`/`SECURITY DEFINER` with indexed lookups; avoid nested seq scans |
| R4 | **Medium** | Confirmed | Feed/list queries run **as anon key + user JWT** through RLS on large `IN` lists | Client `supabaseClient` | Prefer SECURITY DEFINER RPCs for feed page aggregates (already partly done for engagement/leaderboard) |
| R5 | **Low** | Confirmed | Many SECURITY DEFINER admin/notification RPCs | migrations | Keep out of hot interactive path; OK for webhooks |

**Triggers:** Not inventory-expanded in this pass (would need `pg_trigger`). Push/notification path is server-side and outside initial page TTI, but write amplification on likes/comments/follows still affects perceived API latency after mutations.

---

## 11. Next.js rendering and caching findings

| # | Sev | Conf | Finding | Evidence | Fix |
|---|-----|------|---------|----------|-----|
| N1 | **Critical** | Confirmed | Product UX is client-fetched, not RSC-data | Nearly all main `page.tsx` are `"use client"` | Gradual server loaders for above-fold; keep mutations client |
| N2 | **High** | Confirmed | Mega Client Components | community 5261, profile 4175, messages/[id] 3639, feed 2984 LOC | Code-split route sections; dynamic import composers |
| N3 | **High** | Confirmed | Global providers always mount | `app/layout.tsx` | Split marketing vs app layout so marketing skips app warm |
| N4 | **Medium** | Confirmed | Web `appDataCache` hard-miss after 5 minutes | `getCachedTrades` returns null when stale | SWR-style soft stale on web (native already soft) |
| N5 | **Medium** | Confirmed | Leaderboard client `cache: "no-store"` despite server `unstable_cache` 60s | `leaderboardFetch.ts` | Allow default cache / `revalidate` |
| N6 | **Low** | Confirmed | `router.refresh` only onboarding | `onboarding/page.tsx` | OK |
| N7 | **Low** | Confirmed | Unused `createServerClientWrapper` | `supabaseServer.ts` | Dead code; or adopt for true SSR |
| N8 | **Medium** | Suspected | Unstable context / large provider values | `UserProfileProvider` useMemo present | Audit child memoization on Navbar |

**Strict Mode note:** Dev double-mounting effects can double-subscribe briefly; do not treat as production proof. Channel cleanups generally call `removeChannel`.

---

## 12. Media / storage findings

| # | Sev | Conf | Finding | Evidence | Fix |
|---|-----|------|---------|----------|-----|
| M1 | **Medium** | Strong | Lists often use full `image_url` / public URLs without transform params | Feed/profile/community `<img>` patterns | Supabase Image Transform or derived thumbnails |
| M2 | **Low** | Confirmed | `imageUrlCache` only tracks “loaded once” for flicker — not HTTP cache control | `lib/imageUrlCache.ts` | Fine; pair with sized URLs |
| M3 | **Medium** | Confirmed | Storage uploads via progress helper + `getPublicUrl` | messages, feedback, etc. | Ensure list UIs never use original reel video as thumbnail |
| M4 | **Low** | Confirmed | Some marketing uses `next/image` + `sizes`; app UI mostly raw `<img loading="lazy">` | StorageImage, SafeProfileAvatar | Prefer consistent sized loader |

---

## 13. Root causes ranked by measured / evidenced impact

| Rank | Impact | Cause | Confidence |
|------|--------|-------|------------|
| 1 | Request count + TTI | Cold bootstrap fan-out (profile + warm + checklist + Navbar + FreePlan) | Confirmed |
| 2 | Payload + Disk IO | Unbounded full trade history on dash/trades/calendar | Confirmed |
| 3 | Request count + Realtime cost | Feed multi-query merge + 5 channels | Confirmed |
| 4 | Continuous idle load | Room presence heartbeat + unread polling | Confirmed |
| 5 | Server + client cost | Leaderboard loads/pages all public trades | Confirmed |
| 6 | Hydration / navigation | Multi-thousand-line client pages | Confirmed |
| 7 | Duplicate work | Navbar vs inbox unread; QuickTrade vs cache | Confirmed |
| 8 | RLS CPU (unmeasured) | Complex EXISTS policies + bare `auth.uid()` | Strong / needs pg_stat |

---

## 14. Recommended remediation phases

### Phase 1 — Safe high-impact request reductions (do first)

1. **Collapse Navbar badges** into one RPC (`notification_unread_count`, `dm_unread_total`).
2. **FreePlanAccountSlotShell**: subscribe to `appDataCache` only; never initiate competing warm.
3. **QuickTradeModal / Achievement / PostSetup modals**: use cached accounts + profile context; drop `select("*")`.
4. **Soft-stale web trades/accounts** (serve stale, revalidate in background) like native.
5. **Post-create wall refresh**: prepend inserted row; never re-`select("*")` all posts.
6. **TradeSocialLayer likes**: use count head / payload delta; stop refetching all like rows on every event.

### Phase 2 — Query and caching corrections

1. Replace `ensureFullTradesHistory` for dashboard metrics with **aggregate RPCs** (PnL by day, counts, equity series) + keyset “load more”.
2. Profile analytics: same aggregates; stop downloading all public trades.
3. Feed: single `feed_page` RPC returning items + engagement maps.
4. Messages inbox: single hydrate RPC; share cache with Navbar.
5. Explore: lower post cap; ensure trade-meta RPC always used (no scan fallback).

### Phase 3 — Realtime consolidation

1. Feed: one channel (or private topic) with filtered events; multiplex handlers.
2. Community: presence via Realtime presence/broadcast; **delete 60s REST heartbeat** and unread interval when events exist.
3. Ensure Strict Mode–safe single-flight subscribe (ref counts) everywhere like `notificationRealtime`.

### Phase 4 — Database indexes / RPC / RLS

1. Run advisors + `pg_stat_statements` in a **maintenance window** (read-only).
2. Wrap `auth.uid()` in `(select auth.uid())` on hottest policies.
3. Verify indexes for `room_presence(room_id, last_seen)`, leaderboard public trades, feed `not.in` alternatives.
4. Materialize leaderboard snapshots (cron) instead of full scan every cache miss.

### Phase 5 — Larger architectural improvements

1. App-route RSC loaders for dashboard shell metrics and feed first page.
2. Split mega pages; marketing layout without `UserProfileProvider` warm.
3. Adopt a real query library (React Query) **or** formalize the custom cache with request dedupe keys, stale-while-revalidate, and mutation-targeted invalidation.
4. Consider server components + cookie SSR client for first paint auth (unused `supabaseServer.ts`).

---

## 15. Items that need runtime measurement before changing

1. **Actual cold-start waterfall** in Chrome Network (one session only): count REST vs Auth vs Realtime vs Storage.
2. **`pg_stat_statements`** top total_time / calls / mean_time / rows.
3. **Whether `feed_engagement_counts` RPC is always hit** vs fallback (check logs for `[feed] engagement counts RPC`).
4. **P95 size of full trades response** per user cohort (power users vs new).
5. **Leaderboard RPC page count** on cache miss (how many 1000-row loops).
6. **Realtime channel count** in production after navigating Feed → Room → DM → back.
7. **RLS overhead** via `EXPLAIN` (plain) on `profile_posts` select and feed posts — only if needed, not ANALYZE on prod under load.
8. **Idle request rate** with Community room left open for 10 minutes.

---

## 16. Queries / tools used during the audit

| Tool | Purpose | Production load |
|------|---------|-----------------|
| Static repo search (`rg`) | `.from(`, `.rpc(`, channels, `select("*")`, auth, polling, indexes in migrations | None |
| File reads | Providers, caches, feed, presence, leaderboard API, RLS migration samples | None |
| Explore subagents | Architecture map + page inventory | None |
| Supabase MCP | Attempted — **unavailable** | None |
| Supabase CLI / SQL | Not run | None |
| Production browse / load test | **Not run** (per minimize-load rules) | None |
| Full `next build` | **Not run** | None |

---

## 17. Confirmation: read-only / no native changes

- **No application code was modified** for fixes (only this report file was added).
- **No database schema, RLS, indexes, functions, triggers, or config were changed.**
- **No migrations were created or applied.**
- **No deploys.**
- **No destructive or write SQL.**
- **`native-ios/` was not modified.**
- **No production data rows were inspected.**

---

## Finding cards (detail)

### F1 — Cold bootstrap request fan-out

- **Severity:** Critical  
- **Confidence:** Confirmed  
- **Affected page:** All authenticated routes  
- **Exact file/function:** `UserProfileProvider.applyAuthSession`, `warmAppDataCaches`, `fetchGettingStartedChecklistSignals`, `Navbar.fetchUnread` / `fetchUnreadMessages`, `FreePlanAccountSlotShell.load`  
- **Existing behavior:** On session, profile fetch + deferred warm (2–5 queries) + checklist (4–7) + Navbar (≈5) + optional FreePlan ensure  
- **Why expensive:** Multiplies PostgREST + RLS work before first useful page paint  
- **Evidence:** Code trace in §3  
- **Recommended correction:** Phase 1 badge RPC + FreePlan subscribe-only; defer checklist until idle  
- **Expected impact:** −30–50% cold REST on typical login  
- **Risk:** Low–medium (badge correctness)

### F2 — Unbounded full trade history

- **Severity:** Critical  
- **Confidence:** Confirmed  
- **Affected page:** Dashboard, Trades, Calendar (+ Analyst/streaks consumers)  
- **Exact file/function:** `lib/appDataCache.ts` → `ensureFullTradesHistory`  
- **Existing behavior:** After 120-row window, `select(TRADES_APP_SELECT).eq(user_id).order(created_at)` with **no limit**  
- **Why expensive:** Large payloads; RLS per row; client JSON parse; repeated after 5m web stale miss  
- **Evidence:** Lines 441–479, 585–588  
- **Recommended correction:** Aggregate RPCs + paginated history  
- **Expected impact:** Large IO/TTI win for heavy traders  
- **Risk:** Medium (metric parity)

### F3 — Feed merge + multi-channel realtime

- **Severity:** High  
- **Confidence:** Confirmed  
- **Affected page:** Feed  
- **Exact file/function:** `lib/feedContent.ts`, `app/(app)/feed/page.tsx` realtime effects, `fetchFeedEngagementMaps`  
- **Existing behavior:** followingIds → 4 parallel content queries (+ reel hydrate) → engagement RPC; up to 5 channels  
- **Why expensive:** Request count, Realtime fan-out, possible merge top-up loops  
- **Evidence:** Architecture + feed inventory  
- **Recommended correction:** `feed_page` RPC + consolidated channel  
- **Expected impact:** −50% feed REST; fewer sockets  
- **Risk:** Medium

### F4 — Community presence + unread polling

- **Severity:** High  
- **Confidence:** Confirmed  
- **Affected page:** Trade Rooms / Community  
- **Exact file/function:** `lib/roomPresence.ts` `createRoomPresenceSession`; `app/community/page.tsx` 60s unread interval  
- **Existing behavior:** Upsert + fetch presence every 60s; unread refresh every 60s while visible  
- **Why expensive:** Continuous write/read while “idle” in a room  
- **Evidence:** `ROOM_PRESENCE_HEARTBEAT_MS = 60_000`; community `setInterval(..., 60_000)`  
- **Recommended correction:** Realtime presence; event-driven unread  
- **Expected impact:** Removes most idle Supabase traffic on rooms  
- **Risk:** Low–medium (online accuracy)

### F5 — Leaderboard full public trade materialization

- **Severity:** High  
- **Confidence:** Confirmed  
- **Affected page:** Leaderboard  
- **Exact file/function:** `app/api/leaderboard/trades/route.ts` keyset/offset while loops  
- **Existing behavior:** Pages of 1000 until exhausted; client `cache: "no-store"`  
- **Why expensive:** Cache miss = full public trade read; large JSON to browser  
- **Evidence:** `while (true)` RPC paging; `leaderboardFetch.ts`  
- **Recommended correction:** Snapshot table / capped season; allow HTTP cache  
- **Expected impact:** Large server IO reduction on popular page  
- **Risk:** Medium (ranking freshness)

### F6 — Profile over-fetch (`select("*")` / analytics)

- **Severity:** High  
- **Confidence:** Confirmed  
- **Affected page:** Profile  
- **Exact file/function:** `app/profile/[id]/page.tsx` wall posts, rooms, analytics fetches, post-create reload  
- **Existing behavior:** Unbounded selects; sequential prefetch  
- **Recommended correction:** Bounded pages + aggregates; optimistic prepend  
- **Expected impact:** Faster profile TTI  
- **Risk:** Low–medium

### F7 — TradeSocialLayer realtime → full likes refetch

- **Severity:** Medium  
- **Confidence:** Confirmed  
- **Affected page:** Trade detail / cards using `TradeSocialLayer`  
- **Exact file/function:** `app/components/TradeSocialLayer.tsx` channel handler  
- **Existing behavior:** On any `trade_likes` change, `select("user_id")` all likes  
- **Recommended correction:** Adjust count from event; or head count  
- **Expected impact:** Fewer reads under engagement spikes  
- **Risk:** Low

### F8 — RLS `auth.uid()` policy shape

- **Severity:** Medium–High (CPU)  
- **Confidence:** Strong evidence (static); needs measurement  
- **Affected page:** Feed, explore, profile posts, stories  
- **Exact file/function:** e.g. `profile_posts_select_visible`  
- **Existing behavior:** Per-row `auth.uid()` + EXISTS to profiles/followers  
- **Recommended correction:** `(select auth.uid())`; verify indexes  
- **Expected impact:** Lower planning/exec CPU on list queries  
- **Risk:** Low if policy logic unchanged

---

## Appendix A — Unique Supabase call-site counts

| Metric | Count |
|--------|-------|
| `.from("…")` call sites (web, excl. native-ios) | **676** |
| `.rpc("…")` call sites | **28** |
| Combined unique query call sites (from+rpc) | **~704** |
| Client-only `.from` (excl. `app/api`, `lib/server`) | **546** |
| Client-only `.rpc` | **25** |
| `supabase.channel(` create sites | **14** |
| `select("*")` occurrences (incl. count-head) | **30** |

## Appendix B — Estimated requests per major page (incl. cold shell)

| Page | Cold total (shell + page) | Warm return |
|------|---------------------------|-------------|
| Dashboard | ~18–26 | 0–2 |
| Feed | ~22–34 | 0 (+ realtime) |
| Explore | ~21–28 | 0–1 |
| Trades / Calendar | ~18–25 | 0–1 |
| Profile | ~21–34 | 0–2 |
| Messages inbox | ~20–27 | 0 |
| DM thread | ~21–32 | 0–2 |
| Community | ~21–30 then +2/min | presence continues |
| Notifications | ~17–24 | 0–1 |
| Settings | ~15–23 | 0 |
| Leaderboard | ~17–24 (+ server N) | 0–1 |

## Appendix C — Files inspected (primary)

`package.json`, `middleware.ts`, `app/layout.tsx`, `lib/supabaseClient.ts`, `lib/supabase.ts`, `lib/supabaseServer.ts`, `lib/supabaseAdmin.ts`, `lib/supabaseServiceRole.ts`, `app/api/_lib/getRouteUser.ts`, `lib/UserProfileProvider.tsx`, `lib/dataPrefetch.ts`, `lib/appDataCache.ts`, `lib/publicAccountPrivacy.ts`, `lib/notificationRealtime.ts`, `lib/feedContent.ts`, `lib/feedEngagementCounts.ts`, `lib/gettingStartedChecklistSignals.ts`, `lib/roomPresence.ts`, `lib/messageUnread.ts`, `lib/imageUrlCache.ts`, `app/components/Navbar.tsx`, `app/components/FreePlanAccountSlotShell.tsx`, `app/components/TradeSocialLayer.tsx`, `app/(app)/dashboard/page.tsx`, `app/(app)/feed/page.tsx`, `app/explore/page.tsx`, `app/(app)/trades/page.tsx`, `app/calendar/page.tsx`, `app/profile/[id]/page.tsx`, `app/(app)/messages/page.tsx`, `app/messages/[id]/page.tsx`, `app/community/page.tsx`, `app/notifications/page.tsx`, `app/settings/page.tsx`, `app/leaderboard/page.tsx`, `app/api/leaderboard/trades/route.ts`, `lib/leaderboardFetch.ts`, `app/components/QuickTradeModal.tsx`, migrations: `20260609190000_profile_posts_stories_secure_rls.sql`, `20260804230000_phase3_hot_path_indexes.sql`, `20260703160000_trades_performance_indexes.sql`, `20260703170000_query_performance_indexes.sql`, `20260718090000_phase1_messaging_scalability.sql`, plus index/RLS grep across `supabase/migrations/`.

---

*End of audit.*
