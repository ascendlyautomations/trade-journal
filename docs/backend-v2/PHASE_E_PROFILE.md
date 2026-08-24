# Phase E — Profile loading optimization (Profile 1.har)

## Problem (Profile 1.har)

26 Supabase REST operations on Profile open, including:

- 5× per-card `trade_likes` + 5× per-card `trade_comments` (N+1)
- 3× duplicate public `trades` queries (cards, summary, analytics)
- Eager hidden-tab prefetch (posts, reels, achievements, analytics, room)
- Redundant own-profile `profiles` fetch despite Session cache
- Separate follower/following HEAD requests

## Architecture

### Own profile

- Header from `session_profile` when URL segment matches id/username (`resolveOwnProfileHeaderFromSession`)
- Public trades first page + summary from Dashboard/app cache when `trade_window_meta.history_complete`
- Batch trade engagement before cards mount (`batchLoadProfileTradeEngagement`)

### Other profile

- Legacy REST path by default
- Optional `rpc_v1_profile_bootstrap` when `backendV2.profile` flag ON and RPC deployed
- Active tab only — no deferred prefetch chain

### Engagement

- Set-based `trade_likes` + `trade_comments` IN queries (2 requests total for visible cards)
- `TradeSocialProvider.deferCommentsUntilExpanded` — comment rows load on expand only
- Deterministic Realtime channel: `trade-social:{tradeId}` (detail modal still uses Realtime)

## Migration

- Forward: `supabase/migrations/20260821023406_rpc_v1_profile_bootstrap.sql`
- Rollback: `supabase/migrations/rollback/20260821023406_rpc_v1_profile_bootstrap_rollback.sql`
- Deploy order: **SQL on staging → enable flag → web deploy → HAR verify**

## Targets (after RPC + warm cache)

| Metric | Before | Target |
|--------|--------|--------|
| REST ops (Profile) | 26 | 3–5 |
| Per-card likes | 5 | 0 |
| Per-card comments | 5 | 0 |
| Hidden-tab queries | many | 0 on initial open |
