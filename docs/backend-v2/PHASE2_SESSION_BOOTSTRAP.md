# Backend V2 Phase 2 — Session Bootstrap

**Status:** First production Backend V2 RPC. Flag `backendV2.session` defaults **OFF**.

## Audit (pre-change)

### Web (post-auth)
| Request | Source |
|---------|--------|
| `profiles` SELECT (APP_PROFILE_SELECT) | UserProfileProvider |
| `trades` limit 120 + `accounts` | warmAppDataCaches (+1s) |
| notification_preferences, achievements | deferred warm |
| notifications unread count | Navbar |
| DM unread (multi-query) | Navbar / messageUnread |
| admin_users | Navbar |
| followers (per screen) | Feed/Explore later |

Duplicates: profiles often re-read; accounts warmed then re-read; badges separate from profile.

### iOS (post-auth)
| Request | Source |
|---------|--------|
| profile + stats | CurrentUserProfileStore |
| accounts | SessionAccountsStore (on demand) |
| following IDs | SessionFollowingStore (on demand) |
| activity unread + DM badge | Activity / AppIconBadge |

## RPC

`rpc_v1_session_bootstrap()` → `SessionBootstrapV1` JSON:

- viewer + entitlement flags (admin/affiliate/pro)
- session_profile (gate fields)
- accounts_summary
- following_ids
- badges (notifications + DM; rooms null)
- prefs_min
- realtime channel hints

**Not included:** trades, feed, dashboard analytics, messages bodies, profile tabs.

## Feature flag

`backendV2.session` default **OFF** → production path unchanged.

ON (dev): Web uses RPC for profile hydrate + dual-runs REST and logs mismatches. iOS seeds following IDs from RPC; profile/stats remain on existing repos until Profile migration.

## Performance (expected)

| | Before (session-ish) | After (flag ON) |
|--|----------------------|-----------------|
| Requests | ~6–10 (profile + accounts + following + badges + prefs + admin) | **1** RPC (+ dual-run REST in dev only) |
| Payload | many small JSON docs | one composed JSON |
| Screens | unchanged | unchanged |

## Realtime

Unchanged. Bootstrap is initial state only.

## Files

- `supabase/migrations/20260819180000_rpc_v1_session_bootstrap.sql` (applied)
- `lib/backendV2/sessionBootstrap*.ts`
- `lib/UserProfileProvider.tsx` (flag-gated)
- iOS `SessionBootstrapRepository.swift` + contract `session_profile`
- CompositionRoot passes `rpc` into CurrentUserProfileStore
