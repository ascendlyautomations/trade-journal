# Backend V2 Phase 5.1 — Critical Path Decomposition

**Status:** Login → Dashboard first-interaction optimization. **No new RPCs / SQL / ownership changes.**

**Date:** 2026-08-19

---

## Objective

Make Login → Dashboard interactive as early as physically possible while keeping Backend V2 ownership intact.

---

## Critical path timeline (AFTER)

```
Login click
  → Auth (onAuthStateChange SIGNED_IN)
  → UserProfileProvider.applyAuthSession
       ├─ paint from profile cache → loading=false (if cache hit)     [shell unblocked]
       ├─ Session bootstrap RPC  ─────────────────────────────┐
       └─ Dashboard bootstrap RPC (immediate, parallel) ──────┤── Bucket A
                                                              ↓
Dashboard mount (as soon as loading=false + route)
  → useCachedTrades / accounts (cache hit or in-flight warm)
  → first interactive paint (header, filters, actions)
       │
       ├─ idle / deferredSectionsReady
       │    ├─ Copy Trading groups                         Bucket B
       │    ├─ Getting Started signals (2.5s idle)         Bucket B
       │    ├─ Traxs Pro For Life / EA                     Bucket B
       │    ├─ Navbar badges (Session cache / subscribe)   Bucket B
       │    └─ route prefetch (2.5s after interactive)     Bucket B
       │
       └─ on demand: Settings, Achievements, modals…       Bucket C
```

### BEFORE (serialized / deferred)

1. Auth  
2. **Await Session** (shell `loading=true` even with cache when Session flag ON)  
3. `loading=false` → Dashboard mounts  
4. **+1000ms idle delay** then Dashboard warm (or page `ensure*` starts after mount)  
5. Copy Trading + GS + EA compete with paint  

---

## Classification

| Request / work | Bucket | Blocks first interaction? |
|----------------|--------|---------------------------|
| Auth session | A | YES |
| Session bootstrap | A | Cold YES / Cache NO (shell paints) |
| Dashboard bootstrap (trades+accounts) | A | YES (for stats; shell can paint earlier) |
| Navbar badges | B | NO (Session cache) |
| Admin check | B | NO |
| Copy Trading groups | B | NO (deferred to `deferredSectionsReady`) |
| Getting Started checklist signals | B | NO (2.5s deferred) |
| Early Access / Pro-for-life card | B | NO (after deferred sections) |
| Settings prefs warm | B | NO |
| Secondary route prefetch | B | NO |
| Achievements | C | NO |
| Trade/Profile detail | C | NO |
| QuickTrade when closed | C | NO |
| Feed bootstrap | C until /feed | NO |

---

## Code changes

| File | Change |
|------|--------|
| `lib/dataPrefetch.ts` | `startCriticalDashboardWarm` — immediate parallel Dashboard warm; secondary warmers idle @ 2s |
| `lib/UserProfileProvider.tsx` | Cache hit → `loading=false` before Session await; warm starts with Session (parallel) |
| `app/(app)/dashboard/page.tsx` | Copy Trading + Pro-for-life card after `deferredSectionsReady` |
| `lib/GettingStartedProgressProvider.tsx` | Baseline fetch idle timeout 2500ms |

---

## Provider dependency graph

```
UploadProgressProvider          (no network — OK at root)
  UserProfileProvider           CRITICAL — auth + Session; unblocks early on cache
    GettingStartedProgressProvider  POST-PAINT — deferred signals (does not block children)
      OnboardingGateShell         waits loading; uses cached profile when present
        SubscriptionGateShell     waits loading; uses cached profile when present
          App shell / Dashboard
```

Delayed until after first paint: Getting Started network, Copy Trading, EA card, secondary prefs warm, route prefetch.  
On demand: Upload progress UI, QuickTrade, Settings, Achievements.

---

## Parallelization

| Work | Before | After |
|------|--------|-------|
| Session ∥ Dashboard | Dashboard delayed 1s after warm schedule | **Both start at auth** |
| Shell paint ∥ Session | Blocked until Session (flag ON) | **Cache → paint; Session continues** |
| Copy Trading ∥ Dashboard RPC | Competing on mount | **After deferred sections** |

---

## Estimated validation metrics

| Metric | Before (flags ON) | After | Notes |
|--------|-------------------|-------|-------|
| Requests before first paint | Session (+ maybe GS race) | **1–2** (Session; Dashboard in flight) | Cache path paints without waiting Session |
| Time to first Dashboard paint | Session RTT + route | **~Session RTT saved on cache hit**; cold ≈ Session | |
| Time to interactive (trades UI) | Session + ≤1s delay + Dash RTT | **≈ max(Session, Dash)** | Parallel |
| Login→idle | Similar total work | Similar total; **front-loaded less** | Feel faster |
| Requests after first paint | GS, CT, EA, prefs, badges | Same owners, deferred | |

---

## Remaining critical blockers

1. **Auth** round-trip  
2. **Cold Session** when no profile cache (gates need profile)  
3. **Dashboard bootstrap** for non-empty stats (skeleton until trades/accounts land)  
4. Stripe membership reconcile when pending (intentional)

Nothing else should block clicking Quick Trade / Import / filters once shell + empty-or-cached dashboard is up.

---

## Production readiness

Safe for local flag ON. Behavior preserved; only scheduling changed. No ownership / Realtime / RPC changes.
