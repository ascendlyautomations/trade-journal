# Backend V2 Architecture (Phase 1 — Infrastructure)

**Status:** Infrastructure only. No screen migration. No SQL RPCs. No production behavior change.

**Consumers:** Next.js web + native iOS (SwiftUI), same Supabase project.

---

## Phase 2 status

`rpc_v1_session_bootstrap` is live. Flag `backendV2.session` defaults **OFF**. See [PHASE2_SESSION_BOOTSTRAP.md](./PHASE2_SESSION_BOOTSTRAP.md).

## Phase 3 status

`rpc_v1_dashboard_bootstrap` is live. Flag `backendV2.dashboard` defaults **OFF**. See [PHASE3_DASHBOARD_BOOTSTRAP.md](./PHASE3_DASHBOARD_BOOTSTRAP.md).

## Phase 4 status

`rpc_v1_feed_bootstrap` is live. Flag `backendV2.feed` defaults **OFF**. See [PHASE4_FEED_BOOTSTRAP.md](./PHASE4_FEED_BOOTSTRAP.md).

## Phase 4.75 status

Ownership cleanup (no new RPCs). Every remaining request has one owner; redundant warmers/duplicates removed. See [PHASE4_75_OWNERSHIP_CLEANUP.md](./PHASE4_75_OWNERSHIP_CLEANUP.md).

## Phase 5 status

Feed RPC cutover complete when `backendV2.feed` is ON — one `rpc_v1_feed_bootstrap`, no legacy Feed bootstrap fan-out. See [PHASE5_FEED_CUTOVER.md](./PHASE5_FEED_CUTOVER.md).

## Phase 5.1 status

Login → Dashboard critical path decomposition: Session ∥ Dashboard, shell paints from cache, non-critical work deferred. See [PHASE5_1_CRITICAL_PATH.md](./PHASE5_1_CRITICAL_PATH.md).

## Phase 5.2 status

Duplicate request elimination on login → Dashboard idle. See [PHASE5_2_DUPLICATE_AUDIT.md](./PHASE5_2_DUPLICATE_AUDIT.md).

---

## Goals

1. One session bootstrap + one screen bootstrap (future)
2. Realtime owns incremental updates (future)
3. Apps consume stable JSON contracts — not DB schema
4. Dual-run REST + RPC adapters behind feature flags

Phase 1 delivers the shared scaffolding so future phases can cut over safely.

---

## Architecture

```
Web / iOS UI
    │
    │  (unchanged in Phase 1)
    ▼
Existing repositories / REST queries
    │
    │  (future, flag ON)
    ▼
BootstrapProviding ──┬── *RestBootstrapRepository
                     └── *RpcBootstrapRepository
                              │
                              ▼
                     BackendV2RpcClient
                              │
                              ▼
                     Supabase rpc_v1_*_bootstrap
                              │
                              ▼
                     Private SQL helpers + RLS
```

Phase 1 modules:

| Layer | Web | iOS |
|-------|-----|-----|
| Contracts | `lib/backendV2/contracts.ts` | `Data/BackendV2/Contracts/` |
| RPC client | `lib/backendV2/rpcClient.ts` | `Data/BackendV2/BackendV2RPCClient.swift` |
| Flags | `lib/backendV2/flags.ts` | `Data/BackendV2/BackendV2FeatureFlags.swift` |
| Adapters | `lib/backendV2/adapters.ts` | `Data/BackendV2/Adapters/` |
| Versioning | `lib/backendV2/versioning.ts` | `Data/BackendV2/BackendV2Versioning.swift` |
| Telemetry | `lib/backendV2/telemetry.ts` | `Data/BackendV2/BackendV2Telemetry.swift` |

Nothing in `CompositionRoot`, `DataEnvironment`, or app pages imports these for runtime behavior yet.

---

## RPC lifecycle (future)

1. Screen checks `backendV2.<screen>` flag (default OFF)
2. If OFF → existing REST path
3. If ON → `*RpcBootstrapRepository` → `BackendV2RpcClient.call`
4. Transport invokes `rpc_v1_<screen>_bootstrap` with session auth
5. Decode → contract model → ScreenCache / SessionCache
6. Telemetry records timing, bytes, success/failure
7. Realtime patches cache (not full refetch)

---

## Repository adapter pattern

```
DashboardBootstrapProviding
        │
        ├── DashboardRestBootstrapRepository  // wraps today's queries
        └── DashboardRpcBootstrapRepository   // calls rpc_v1_dashboard_bootstrap
```

Same public interface. Screens depend on the protocol/interface only.  
Phase 1 defines interfaces + an unimplemented RPC stub factory. No DI wiring.

---

## Feature flag strategy

| Flag | Default |
|------|---------|
| `backendV2.session` | OFF |
| `backendV2.dashboard` | OFF |
| `backendV2.feed` | OFF |
| `backendV2.profile` | OFF |
| `backendV2.messages` / `backendV2.messaging` | OFF |
| `backendV2.messageThreads` | OFF |
| `backendV2.rooms` | OFF |
| `backendV2.roomPresence` | OFF |
| `backendV2.activity` | OFF |
| `backendV2.calendar` | OFF |
| `backendV2.explore` | OFF |
| `backendV2.leaderboard` | OFF |
| `backendV2.tradeDetail` | OFF |
| `backendV2.settings` | OFF |
| `backendV2.propFirm` | OFF |

**Total:** 15 flags (see `lib/backendV2/flags.ts`). Enable one flag per cutover phase after the SQL RPC exists and dual-run passes.

---

## Versioning strategy

- Public RPC names: `rpc_v1_<name>_bootstrap`
- Payload `meta.contract_version`: `"v1"`
- Additive fields OK within v1
- Breaking changes → `rpc_v2_*` + dual publish window
- Clients pass `p_contract_version` when RPCs are implemented

Utilities: `BackendV2RpcNames`, `assertContractVersion` / Swift `BackendV2Versioning`.

---

## Migration strategy

1. Phase 1 — infrastructure (this doc)
2. Phase 2 — `rpc_v1_session_bootstrap` SQL + dual-run, flag still OFF then ON
3. Later — Feed, Leaderboard, Profile, Messaging, Trading screens, rest
4. Delete old REST read paths only after both platforms are stable on RPC
5. Rollback = flip flag OFF (no big-bang)

---

## Realtime integration strategy

- Bootstraps hydrate L1 SessionCache / L2 ScreenCache
- Realtime events patch those caches (never replace ownership)
- No polling for presence/unread once Rooms/Messaging migrate
- Soft TTL revalidate remains as safety net

Event → contract patch matrix lives in Phase 0 design canvas.

---

## Contract ownership

| Object | Owner domain | Contract home |
|--------|--------------|---------------|
| Viewer + entitlement | Identity / Entitlements | Session |
| Following IDs | SocialGraph | Session (+ echo in Feed/Explore) |
| Badges | Notifications + Messaging + Rooms | Session |
| Accounts summary | Trading | Session + Dashboard/Calendar/Settings |
| Feed items + engagement | Feed + Engagement | Feed |
| Follow edge | SocialGraph | Profile |
| DM/room previews | Messaging / Rooms | Messages / Rooms |
| Notifications list | Notifications | Activity |

---

## Telemetry

Development logging only (no analytics backend required):

- execution time
- decode time
- payload size
- success / failure
- cache hit / miss (caller-supplied)
- error code

---

## Testing

- Web: `npm run test:backend-v2` and targeted phase scripts (see [README.md](./README.md))
- Reel media: `npm run test:reel-media`
- iOS: `BackendV2ContractTests` in TradeTraxsTests

Golden fixtures must decode on both platforms with identical `meta.contract_version`.
