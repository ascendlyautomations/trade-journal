# Backend V2 Phase 4 — Feed Bootstrap

**Status:** `rpc_v1_feed_bootstrap` live. Flag `backendV2.feed` defaults **OFF**.

## 1. Feed REST audit (Feed page mount → first paint)

| Endpoint / call | Table(s) | Why | Owner | Bootstrap owner | Remain? | Move into Feed RPC? |
|-----------------|----------|-----|-------|-----------------|---------|---------------------|
| `followers` SELECT | followers | Scope following IDs | **Session** (intended) / Feed (actual) | Session | Echo only | **Yes** (as `following_ids_echo`; Session remains owner) |
| `posts` range | posts (+ trades, profiles, reels embeds) | Trade cards | **Feed** | Feed | No (flag ON) | **Yes** |
| `profile_posts` range | profile_posts | Profile cards | **Feed** | Feed | No | **Yes** |
| `achievement_posts` range | achievement_posts, achievements | Achievement cards | **Feed** | Feed | No | **Yes** |
| `reels` range | reels | Reel cards | **Feed** | Feed | No | **Yes** |
| `reels` by trade_id | reels | Trade-attached reel hydrate | **Feed** | Feed | No | **Yes** (embedded) |
| `rpc feed_engagement_counts` | likes/comments* | Like/comment counts + liked_by_me | **Feed** | Feed | No | **Yes** |
| `stories` + `profiles` | stories, profiles | Stories bar (following) | **Feed** | Feed | No | **Yes** |
| Session bootstrap / profile | profiles, … | Auth gate | **Session** | Session | Yes | **No** |
| Dashboard warm trades/accounts | trades, accounts | Prefetch | **Dashboard** | Dashboard | Yes | **No** |
| Realtime INSERT channels | posts, profile_posts, achievement_posts, reels | Live prepend | **Realtime** | — | Yes | **No** (never re-bootstrap) |
| Realtime reel_likes / stories | reel_likes, stories | Live patches | **Realtime** | — | Yes | **No** |
| Comment bodies / bookmarks | comments*, saved_* | Lazy / unused | Feed lazy / — | — | Lazy OK | **No** |

**Typical cold following/`all` before:** ~6–8 HTTP + Realtime.  
**After (flag ON):** **1** Feed RPC (+ optional dual-run REST in dev).

## 2. Ownership map

```
Feed page loadPosts
        │  (flag ON only)
        ▼
loadFeedBootstrapForUser   ← sole orchestrator (single-flight)
        │
        ├── FeedRpcBootstrapRepository  ← sole network owner
        │         └── rpc_v1_feed_bootstrap
        └── (dev dual-run) FeedRestBootstrapRepository
                └── seeds feedSessionCache / storiesSessionCache
```

Session fields never appear in this RPC (viewer / badges / prefs / entitlement).  
`following_ids_echo` is an echo for Feed scope — Session owns SocialGraph.

## 3. SQL

`supabase/migrations/20260820220000_rpc_v1_feed_bootstrap.sql`  
Applied remotely via Supabase MCP.

Signature: `rpc_v1_feed_bootstrap(p_scope, p_content_filter, p_limit, p_cursor) → jsonb`  
SECURITY INVOKER · cursor = `created_at` of last item · limit default 8.

Payload: items, authors, engagement, stories, story_authors, next_cursor, page_meta, following_ids_echo.

## 4–7. Contracts / repos / flag / dual-run / Realtime

| Piece | Location |
|-------|----------|
| Contracts | `lib/backendV2/contracts.ts` + iOS `FeedBootstrapV1` |
| Repos | `feedBootstrapRepository.ts` |
| Cache / flight | `feedBootstrapCache.ts`, `feedBootstrapSingleFlight.ts` |
| Flag | `backendV2.feed` / `NEXT_PUBLIC_BACKEND_V2_FEED` |
| Dual-run | `NEXT_PUBLIC_BACKEND_V2_DUAL_RUN=1` (dev, first page) |
| Wire | `app/(app)/feed/page.tsx` `loadPosts` when flag ON |
| Realtime | Unchanged — patches posts/likes/stories; **does not** re-call bootstrap |

## 8–10. Request counts / readiness

| | Flag OFF | Flag ON |
|--|----------|---------|
| followers REST | 1 | **0** (echo inside RPC) |
| content REST (4 streams) | 4+ | **0** |
| engagement RPC | 1 | **0** (inlined) |
| stories REST | 0–2 | **0** (inlined; cache seeded) |
| Feed bootstrap RPC | 0 | **1** |
| **Typical cold Feed fan-out** | **~6–8** | **1** |

Payload: one composed JSON (~tens of KB for 8 cards) vs multiple small docs.  
Latency: one RTT vs 6–8 sequential/parallel RTTs.

**Production readiness:** Ready for **dev enable** behind flag. Recommend dual-run for 1–2 days, then enable for web; wire iOS `FeedRpcBootstrapRepository` before flipping iOS flag. Do not enable in production until dual-run is clean and Realtime prepend/patch paths are smoke-tested.

## Enable (dev)

```bash
# .env.local
NEXT_PUBLIC_BACKEND_V2_FEED=1
# optional dual-run:
NEXT_PUBLIC_BACKEND_V2_DUAL_RUN=1
```

Or `localStorage.setItem("backendV2.feed", "1")` then reload.
