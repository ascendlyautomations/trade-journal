# Backend V2 Phase 2.5 — Session Cleanup

## Why Session RPC ran twice

**Cause:** Supabase emits `INITIAL_SESSION` then `SIGNED_IN` on login. Both entered `applyAuthSession` when `profileRef` was not yet set (race). Provider remounts can also re-enter before cache existed.

**Fix:**
1. In-flight coalesce + **cache-first** in `loadSessionBootstrapForUser` (second caller gets cache / shared promise — **0 second RPC**)
2. Skip `SIGNED_IN` reload when session bootstrap cache already exists for the user

## Redundant REST removed (flag ON)

| Request | Was called by | Now |
|---------|---------------|-----|
| `profiles` hydrate | UserProfileProvider | Session RPC only |
| notifications unread (initial) | Navbar | Session badges cache |
| DM unread (initial) | Navbar / NativeIosBottomNav | Session badges cache |
| `admin_users` | Navbar admin check | Session `entitlement.flags.is_admin` |
| `notification_preferences` warm | dataPrefetch | Skipped (prefs_min in session) |

Realtime still refreshes badge counts on events and **patches** the session cache (does not re-run bootstrap).

## REST intentionally kept

| Request | Owner | Why |
|---------|-------|-----|
| `trades` warm (120) | Dashboard / trading | Not in Session RPC |
| `accounts` full SELECT | Dashboard / settings | Session only has summary; UI needs prop-firm fields |
| `achievements` warm | Getting started / streaks | Not session-owned |
| Settings `fetchSettingsProfileRow` | Settings screen | Full settings editor (on demand) |
| Dashboard refresh / mutations | Dashboard | Force reload after import |
| Feed / Profile / Messages content | Those screens | Phase 3+ |

## Updated login waterfall (flag ON)

```
Auth INITIAL_SESSION
  → rpc_v1_session_bootstrap (once)
  → seed session cache + profile caches
SIGNED_IN (same user)
  → skip (cache / profile present)
Navbar
  → badges from session cache (no REST)
Admin
  → is_admin from session cache
+1s warm
  → trades + full accounts (Dashboard-owned)
  → skip notification_preferences
Realtime
  → patch session badges / profile slice
```

## Before vs After (auth → Dashboard paint, flag ON)

| Metric | Before cleanup | After |
|--------|----------------|-------|
| Session RPC | 2× (duplicate) | **1×** |
| profiles REST | 0–1 (if fallback) | **0** |
| badge REST initial | 2+ (notif + DM) | **0** |
| admin_users | 1 | **0** |
| notification_preferences warm | 1 | **0** |
| trades + accounts warm | kept | kept |

## Session complete enough for Phase 3?

**Yes** — Session ownership is singular, duplicate bootstrap fixed, shell no longer re-fetches session fields. Feed Bootstrap can proceed next; do not fold feed into Session.
