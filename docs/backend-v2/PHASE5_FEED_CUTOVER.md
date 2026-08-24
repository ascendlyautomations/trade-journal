# Backend V2 Phase 5 — Complete Feed RPC Cutover

**Status:** Feed page uses `rpc_v1_feed_bootstrap` when `backendV2.feed` is ON. Legacy REST repository retained for flag OFF + dual-run.

**Date:** 2026-08-19

---

## 1. Why the Feed RPC was not in the HAR

**Exact runtime gate:** `isBackendV2Enabled("feed")` returned **false**.

Trace:

```
Feed page loadPosts
  → if (isBackendV2Enabled("feed") && !demo) { loadFeedBootstrapForUser → RPC }
  → else { legacy REST fan-out }
```

Resolution order (`lib/backendV2/flags.ts`):

1. test override  
2. `localStorage["backendV2.feed"]`  
3. `NEXT_PUBLIC_BACKEND_V2_FEED`  
4. **default `false`**

Local `.env.local` had Session + Dashboard enabled (`=1`) but **did not set** `NEXT_PUBLIC_BACKEND_V2_FEED`.  
Wiring in `app/(app)/feed/page.tsx` was already present from Phase 4 — the flag was never turned on, so the browser never called `supabase.rpc('rpc_v1_feed_bootstrap')`.

---

## 2. Cutover changes (this phase)

| Change | Purpose |
|--------|---------|
| `NEXT_PUBLIC_BACKEND_V2_FEED=1` in `.env.local` | Enable Feed RPC for local HAR |
| Resolve default mode from Session `following_ids` before first load | One Feed RPC (avoid global→following double call) |
| Gate `useActiveStories` until `feedReady` when feed flag ON | Stop parallel stories REST before bootstrap seeds `storiesSessionCache` |
| Keep `FeedRestBootstrapRepository` | Flag OFF + dual-run only |

**No SQL changes.** RPC already applied.

---

## 3. Ownership (unchanged)

| Domain | Owns |
|--------|------|
| **Feed** | items, pagination, authors, engagement, stories (bootstrap seed) |
| **Session** | following_ids (echoed only), viewer, badges, prefs, entitlement |
| **Dashboard** | trades, accounts, analytics |
| **Realtime** | INSERT prepend + like/comment/story patches — **never** re-bootstrap |

Feed bootstrap writes **Feed cache** (+ stories session cache for the stories bar). It does **not** write Session / Dashboard / Profile / Messages caches.

---

## 4. Initial load requests

### BEFORE (flag OFF)

~6–8 HTTP: followers + posts + profile_posts + achievement_posts + reels + `feed_engagement_counts` + stories(+profiles)

### AFTER (flag ON)

**1** × `rpc_v1_feed_bootstrap`

No bootstrap GETs for posts / profile_posts / achievement_posts / reels / stories / feed_engagement_counts.

### Remaining REST (expected — not bootstrap)

| Request | Owner | Why |
|---------|-------|-----|
| Realtime INSERT hydrate (`posts`/`profile_posts`/… by id) | Realtime → Feed cache patch | Single-row fetch after live INSERT |
| Comment thread lazy load | Feed lazy | On open comments |
| Deep-link row + engagement | Feed deep-link | Only when URL targets a post |
| Stories refetch on Realtime story change | Feed stories | Patch after bootstrap |
| Session / Dashboard RPCs | Session / Dashboard | Other owners |

---

## 5. Enable

```bash
# .env.local
NEXT_PUBLIC_BACKEND_V2_FEED=1
# restart next dev after changing NEXT_PUBLIC_*
```

Or `localStorage.setItem("backendV2.feed", "1")` then reload.

Dual-run (dev only): `NEXT_PUBLIC_BACKEND_V2_DUAL_RUN=1` — keep **off** for clean HAR.

---

## 6. Production readiness

**Dev-ready** with Session + Dashboard + Feed flags ON and dual-run OFF.

Before production:

1. Smoke Realtime prepend + like patches with flag ON  
2. Confirm iOS Feed RPC adapter wired (still stub)  
3. Dual-run clean for 1–2 days optional  
4. Then enable `NEXT_PUBLIC_BACKEND_V2_FEED` in hosting env
