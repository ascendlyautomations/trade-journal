# Native iOS — Backend V2 Data-Loading Parity Audit

**Date:** 2026-08-24  
**Scope:** `native-ios/` only — audit and roadmap; no migration implemented.

## Executive Summary

Native iOS uses a **custom PostgREST transport** (not the official Supabase Swift SDK) with **REST-first** screen bootstraps. Backend V2 is **scaffolded**: 19 RPC names, Swift contract models, feature flags (all default OFF), and contract tests — but **only `rpc_v1_session_bootstrap` is wired**, and even that runs **alongside** existing profile/stats REST on cold launch.

**GRDB is not implemented.** Persistence is in-memory session stores + JSON disk cache (`SessionDiskCache`).

Web has **two RPCs native lacks in versioning**: `rpc_v2_messaging_bootstrap`, `rpc_v1_conversation_thread_bootstrap`, `rpc_v1_prop_firm_bootstrap`, `rpc_v1_getting_started_signals`.

---

## 1. Supabase Client Ownership Map

| Owner | Path | Responsibility |
|-------|------|----------------|
| `SupabaseInfrastructure.make` | `Data/Supabase/SupabaseProviders.swift` | Builds database, storage, realtime, RPC clients |
| `DataEnvironment.make` | `Data/DataEnvironment.swift` | Wires repos, caches, `RealtimeHub`, session stores |
| `CompositionRoot.bootstrap` | `App/CompositionRoot.swift` | App-level DI, starts RealtimeHub |
| `SupabaseDatabaseClient` | `Data/Supabase/SupabaseDatabaseClient.swift` | PostgREST select/insert/update/delete/rpcData |
| `SupabaseTransport` | `Data/Supabase/SupabaseTransport.swift` | Auth headers, host routing (.supabase / .bff) |
| `BackendV2RPCClient` | `Data/BackendV2/BackendV2RPCClient.swift` | Typed V2 RPC calls + contract validation |
| `URLSessionNetworkClient` | `Platform/Networking/Core/NetworkClient.swift` | BFF `/api/*` routes |
| `LiveSupabaseRealtimeProvider` | `Data/Supabase/SupabaseProviders.swift` | WebSocket + postgres_changes |
| `RealtimeHub` | `Data/Realtime/RealtimeArchitecture.swift` | Connection lifecycle, channel registry |
| `SessionScopedCaches` | `App/SessionScopedCaches.swift` | Logout / account-switch invalidation |

**Credentials:** `AppConfiguration` + `SecretsLoader` — anon/publishable key only. Explicit comment: service-role keys must never ship in the iOS bundle.

---

## 2. Request Counts (production `TradeTraxs/TradeTraxs`)

| Category | Count |
|----------|-------|
| PostgREST table ops (`database.select/insert/…`) | **~118** call sites |
| Table name literals (`from:` / `into:`) | **~98** |
| Legacy `rpcData(` (feature repos) | **16** call sites / **14** distinct functions |
| Backend V2 RPC invoked at runtime | **1** (`rpc_v1_session_bootstrap`, flag-gated) |
| BFF `/api/*` routes | **9** |
| GRDB | **0** |
| Production `Timer` / `DispatchSourceTimer` polling | **0** |
| 60s idle `Task.sleep` placeholders | **3** (Dashboard, Calendar, Prop Firm) |

---

## 3. Screen Request Map (abbreviated)

See final report §2 for full table. Key patterns:

- **Cold launch (auth):** session restore (Keychain) → optional session RPC → profile + stats REST (2 queries minimum).
- **Dashboard:** accounts REST + owner trades (≤500) + deferred achievements; registry realtime only.
- **Feed:** multi-table timeline merge + engagement prefetch + postgres_changes on posts.
- **Messages home:** conversations (100) + member rooms + unread RPCs; realtime on read cursors + room messages.
- **DM thread:** paginated messages + realtime inserts; mark-read RPC on open.
- **Leaderboard:** BFF `/api/leaderboard/trades` (or legacy RPC pages); client-side rank.
- **Prop Firm:** 500 trades filtered client-side; registry realtime placeholder.

---

## 4. Backend V2 Compatibility Matrix

| RPC (live web) | Native enum | Invoked | Models | Safe unchanged |
|----------------|-------------|---------|--------|----------------|
| `rpc_v1_session_bootstrap` | yes | yes (flag) | yes | **yes** — partial adoption only seeds following/badges |
| `rpc_v1_dashboard_bootstrap` | yes | no | yes | **yes** — replace accounts+trades+metrics fan-out |
| `rpc_v1_feed_bootstrap` | yes | no | yes | **yes** — must preserve scope/filter/cursor/engagement |
| `rpc_v1_profile_bootstrap` | yes | no | yes | **mostly** — tab lazy loads may still need tab RPCs |
| `rpc_v2_messaging_bootstrap` | **no** | no | partial (V1 shape) | **needs native model update** |
| `rpc_v1_messaging_bootstrap` | yes | no | yes | legacy fallback only |
| `rpc_v1_conversation_thread_bootstrap` | **no** | no | **no** | **add contract** before thread migration |
| `rpc_v1_room_bootstrap` | yes | no | yes | **yes** — rooms currently fragmented |
| `rpc_v1_prop_firm_bootstrap` | **no** | no | **no** | **add contract** — native computes client-side today |
| `rpc_v1_getting_started_signals` | **no** | no | **no** | optional — onboarding is navigation-only today |
| Profile tab RPCs (4) | yes | no | stubs in contracts | adopt with profile bootstrap |
| `rpc_v1_leaderboard_bootstrap` | yes | no | yes | **gap** — native uses BFF + legacy RPC today |
| `rpc_v1_calendar_bootstrap` | yes | no | yes | yes |
| `rpc_v1_trades_list_bootstrap` | yes | no | yes | yes |
| `rpc_v1_trade_detail_bootstrap` | yes | no | yes | yes |
| `rpc_v1_activity_bootstrap` | yes | no | yes | yes |
| `rpc_v1_explore_bootstrap` | yes | no | yes | yes |
| `rpc_v1_settings_bootstrap` | yes | no | yes | yes |

---

## 5. Recommended Implementation Batches

### N1 — Session + Dashboard
- Wire `SessionRpcBootstrapRepository` as primary session path (flag default ON after validation).
- Implement `DashboardRpcBootstrapRepository`; map to `SessionOwnerTradesStore` / accounts.
- Process-wide single-flight: `viewerID + rpc_v1_session_bootstrap`, `viewerID + dashboard + accountID`.
- Extend `SessionDiskCache` for bootstrap blobs; logout via `SessionScopedCaches`.

### N2 — Feed + Profile
- `FeedRpcBootstrapRepository` behind `backendV2.feed`.
- `ProfileRpcBootstrapRepository` + tab RPCs for lazy tabs.
- Realtime patch targets in `FeedScreenViewModel` / `ProfileContentStore`.

### N3 — Messages
- Add `rpc_v2_messaging_bootstrap` to `BackendV2Versioning` + decode models.
- Add `rpc_v1_conversation_thread_bootstrap` contract.
- GRDB seam for thread messages (optional JSON cache first).
- Read-mark semantics unchanged; single-flight inbox bootstrap.

### N4 — Trade Rooms
- `RoomsRpcBootstrapRepository`; unify sections/messages/unread.
- Presence lifecycle documented for iOS background (do not copy web tab semantics).

### N5 — Prop Firm + residual
- Add `rpc_v1_prop_firm_bootstrap` contract.
- Leaderboard: evaluate BFF vs `rpc_v1_leaderboard_bootstrap`.
- Remove redundant REST where RPC subsumes; keep mutations direct.

---

## 6. Manual Network Capture Checklist (pending measurements)

Use Xcode Instruments Network + DEBUG `DashboardLoadProbe` / `SessionNetworkProbe`:

1. Cold launch → count PostgREST + BFF
2. Dashboard first paint vs full hydration
3. Feed filter switch (Following/Global × content type)
4. Own profile cold vs warm tab switch
5. Other profile
6. Messages inbox
7. DM thread open + pagination
8. Trade room open
9. Prop Firm account detail
10. 5 min idle (verify no polling except WS heartbeat)
11. Background 90s → foreground reconciliation
12. Logout → different user login (cache isolation)

**Agent session:** measurements not captured — mark **pending**.

---

## 7. Security Checklist

- [x] Anon/publishable key only in client config
- [x] No service-role in source (verified grep)
- [x] Session tokens in Keychain via `SecureCredentialStoring`
- [x] `SessionScopedCaches` clears viewer data on logout
- [x] DEBUG logging redacts message bodies (OSLog privacy modifiers in places)
- [ ] Runtime audit: ensure no RPC passes client-supplied `viewer_id` when `auth.uid()` expected (review per-RPC at implementation)

---

*Generated by native parity audit — implementation not started.*
