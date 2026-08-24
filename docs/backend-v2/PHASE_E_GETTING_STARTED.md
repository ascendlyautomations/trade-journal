# Phase E — Getting Started checklist RPC (HAR 11)

## Problem (HAR 11)

`GettingStartedProgressProvider` deferred seven Supabase REST operations (+ seven OPTIONS) while Session (~13s) and Dashboard (~13s) RPCs were still in flight:

1. GET `profiles` — onboarding flags
2. HEAD `trades` — total count
3. HEAD `profile_posts`
4. HEAD `followers`
5. HEAD `trades` — public count
6. GET `room_members` (+ rooms embed)
7. GET `trades` — latest qualifying private trade

## Frozen contract

**Owner:** `GettingStartedProgressProvider` → `fetchGettingStartedChecklistSignals`

**Consumers:** `useGettingStartedProgress()` in dashboard, mobile entry; popups/sticky derive from provider state only.

| Field | Semantics |
|-------|-----------|
| `onboardingCompleted` | `profiles.onboarding_completed === true` |
| `hasSeenGettingStartedIntro` | `profiles.has_seen_getting_started_intro === true` |
| `hasSeenOnboardingCompletePopup` | `profiles.has_seen_onboarding_complete_popup === true` |
| `tradeCount` | Exact count of user's trades (checklist: `> 0`) |
| `profilePostCount` | Exact count of `profile_posts` rows |
| `followCount` | Exact count of `followers` where user is follower |
| `hasEverJoinedOtherRoom` | Any `room_members` row where joined room's `owner_user_id <> auth.uid()` |
| `hasPublicTrade` | Any trade with `is_public = true` |
| `firstPrivateTradeId` | Latest trade with `is_public = false`, `mode <> 'backtest'`, ordered by `created_at desc` |

## Local cache reuse (no duplicate critical-path work)

| Signal | Trusted local source |
|--------|---------------------|
| Profile flags | `UserProfileProvider` preloaded profile |
| `tradeCount` / public / private | `getCachedTrades()` → `deriveTradeChecklistSignalsFromTrades` |
| `tradeCount` (no trades cache) | Dashboard `trade_window_meta.total_trade_count` |
| `followCount` | Session bootstrap `following_ids.length` |

RPC returns a full baseline; `mergeGettingStartedSignals` overlays local cache when present. Final checklist is identical regardless of arrival order.

## RPC

- **Migration:** `supabase/migrations/20260821021641_rpc_v1_getting_started_signals.sql`
- **Function:** `public.rpc_v1_getting_started_signals()`
- **Security:** `SECURITY INVOKER`, `auth.uid()` only, rejects anonymous, `REVOKE PUBLIC/anon`, `GRANT authenticated`

## Client

- Single RPC replaces seven REST calls when deployed
- Legacy seven-query path when RPC missing (session-cached unavailable flag)
- Scheduled only after Session (+ Dashboard when enabled) bootstrap settles or 3s timeout
- Module in-flight dedupe + sessionStorage baseline cache unchanged

## Targets

- Checklist REST: 7 → 1
- Checklist network (incl. OPTIONS): 14 → ≤ 2
- No refetch on route transition after baseline resolved
