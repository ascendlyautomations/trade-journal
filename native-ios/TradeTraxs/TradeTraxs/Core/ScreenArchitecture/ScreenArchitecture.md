# Unified Screen Architecture Framework

Native iOS only. Profile, Feed, and Messaging are the reference implementations.

## Ownership

```
One screen (or shared domain)
    → one bootstrap (`*Bootstrap.load`)
    → one state (`*State` conforming to ScreenStateModeling)
    → render-only child views / section VMs
```

Child views **must never** perform the initial repository request. They may:

- render from applied bootstrap / bound state
- trigger **screen-owned** actions (`refresh`, `loadMore`, mutations)
- observe session caches that the screen already primed

## Standard lifecycle API

Every screen owner should expose (names may wrap existing APIs):

| API | Role |
|-----|------|
| `bootstrapIfNeeded()` | First coordinated load; skip if `didBootstrap` |
| `refresh()` | Explicit / pull-to-refresh reload |
| `loadMore()` | Pagination; no-op if not paginated |
| `subscribeRealtime()` | Start watchers |
| `unsubscribeRealtime()` | Stop watchers |
| `handleRealtimeEvent(_:)` | Optional; mutate state from payloads |

Protocols: `ScreenLifecycle`, `ScreenRealtimeHandling`, `ScreenBootstrap`, `ScreenStateModeling`.

## Common state fields

Map feature-local enums into:

- `screenPhase` → `ScreenPhase` (idle / loading / loaded / failed)
- `didBootstrap`
- `isRefreshing`
- `pagination` → `ScreenPaginationSnapshot` (or `.none`)
- `screenErrorMessage`
- `lastUpdated` (optional)

Domain collections stay on the feature state.

## Composition (not inheritance)

```
ScreenViewModel
  ├─ repositories / session stores (injected)
  ├─ var state: FeatureState
  ├─ FeatureBootstrap.load(context)   // static fan-out
  └─ realtime retain / release
```

Prefer `enum FeatureBootstrap: ScreenBootstrap` + `@Observable` / `@MainActor` view models.

## Migration checklist (future screens)

1. Add `FeatureState` with phase, `didBootstrap`, refresh/pagination flags; conform `ScreenStateModeling`.
2. Add `FeatureBootstrap` with one concurrent `load` assembling the first paint.
3. Add `FeatureScreenViewModel` owning state; implement `ScreenLifecycle` (thin wrappers OK).
4. Wire the root view to call `bootstrapIfNeeded` / `refresh` / realtime retain-release only.
5. Convert section VMs to `applyBootstrap` / bind — remove their initial repository loads.
6. Keep session caches for cross-tab reuse; screen still owns first paint.
7. Add a focused experience / bootstrap test (happy path + no duplicate child fetch).

## Reference screens — what already satisfies the framework

| Concern | Profile | Feed | Messaging |
|---------|---------|------|-----------|
| One screen / domain owner | `ProfileScreenViewModel` | `FeedScreenViewModel` | `MessagingDomain` (+ home façades) |
| Coordinated bootstrap | `ProfileBootstrap` | `FeedBootstrap` | `MessagingBootstrap` |
| Single state snapshot | `ProfileState` | `FeedState` | `MessagingState` |
| Render-only children | Section VMs `applyBootstrap` | `FeedHomeView` binds state | Homes present inbox store + domain state |
| `bootstrapIfNeeded` | ✅ (also `onAppear`) | ✅ (alias of `loadIfNeeded`) | ✅ (alias of `bootstrapHomeIfNeeded`) |
| `refresh` | ✅ | ✅ | ✅ (`refreshHome` / alias) |
| `loadMore` | Screen no-op; sections paginate | ✅ (+ `loadMoreIfNeeded`) | Home no-op (threads paginate) |
| Realtime | None on screen VM | `subscribe` / `unsubscribe` / `handleRealtimeEvent` | **Retain-counted** `retainRealtime` / `releaseRealtime` |
| `ScreenStateModeling` | ✅ | ✅ | ✅ |
| `ScreenBootstrap` | ✅ | ✅ (`load` → `loadInitial`) | ✅ (`load` → `loadHome`) |

## Minor consistency gaps (non-blocking)

1. **Naming:** Feed still exposes `loadIfNeeded` / `stopRealtime`; Messaging exposes `bootstrapHomeIfNeeded` / `refreshHome`. Standard names are thin aliases — keep legacy call sites.
2. **Profile realtime:** No screen-owned realtime; `subscribeRealtime` / `unsubscribeRealtime` are intentional no-ops.
3. **Profile pagination:** Trades cursor lives on state; page-in remains on section VMs after bootstrap (acceptable for tabbed shell).
4. **Messaging dual bootstrap:** `loadHome` vs `loadRoomsOnly` — protocol `load` maps to full home; rooms-only stays domain-specific.
5. **Messaging realtime:** Prefer `ScreenRealtimeRetaining` over bare subscribe when Messages and Trade Rooms overlap.
6. **Feature-local `Phase` enums:** Kept for call-site compatibility; mapped via `screenPhase`.
7. **`lastUpdated` / `isRefreshing`:** Aligned on all three states; Profile previously lacked them (UI unchanged).

## Non-goals

Do not change UI, business logic, auth, permissions, Supabase contracts, or migrate extra screens in the same PR as framework extraction.
