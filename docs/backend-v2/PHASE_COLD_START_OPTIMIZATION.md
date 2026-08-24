# Cold Start Optimization — Landing, Login, Dashboard

Web-only cold-start phase. Feed B2+, Messages, and full Realtime consolidation are **not** started here.

## Status

| Item | State |
|------|--------|
| Applied to production | **No** |
| native-ios/ touched | **No** |
| Auth / RLS / FreePlan behavior | **Preserved** |
| HAR 8 baseline | Auth ~731ms, Session ~1.20s, Dashboard ~1.25s, copy-trading waterfall ~527ms |

---

## Step 1 — Request inventories (code audit + HAR 8 baseline)

### A. Anonymous `/` (signed out, idle)

| Category | Before | After (expected) |
|----------|--------|------------------|
| Supabase Auth | `INITIAL_SESSION` (session discovery) | Same — required for login-state nav |
| Supabase REST/RPC (app tables) | **None client-side** | **None** |
| Realtime WebSocket | **None** (no session) | **None** |
| Early access | `GET /api/early-access/config` | Same (server route, not direct DB from browser) |
| Server RSC (landing) | Featured trades + reviews via ISR/Suspense | Unchanged (server-side marketing content) |

### B. `/login` before submission

| Category | Before | After |
|----------|--------|-------|
| Supabase Auth | Session discovery only | Same |
| App-table queries | **None** | **None** |
| Realtime | **None** | **None** |
| Dashboard/Session RPC | **None** until `SIGNED_IN` | **None** until `SIGNED_IN` |

### C. Login → Dashboard (authenticated cold start)

| Category | HAR 8 baseline | Target |
|----------|----------------|--------|
| Auth token | 1× ~731ms | 1× |
| Session RPC | 1× ~1.20s | 1× (parallel with Dashboard) |
| Dashboard RPC | 1× ~1.25s | 1× |
| Realtime | 1× WebSocket | 1× |
| Avatar | Lazy img in Navbar | Non-blocking |
| Copy trading | groups + accounts (~527ms waterfall) | **0 on cold start** unless saved copy-group filter or picker opened |
| Route prefetch | `/trades`, `/feed` after idle | Deferred (unchanged from B1) |

---

## Step 2–4 — Ownership chain (authenticated)

```
SIGNED_IN / INITIAL_SESSION (app route or fresh sign-in)
  → UserProfileProvider.applyAuthSession
      → cached profile → loading=false (shell unblock)
      → warmAppDataCaches (SIGNED_IN or app route) → startCriticalDashboardWarm
          → loadDashboardBootstrapForUser (parallel, not awaited by Session)
      → loadSessionBootstrapForUser (await)
      → runDeferredBootstrap → profile Realtime (app routes only)
  → dashboard/page.tsx
      → useCachedTrades / useCachedAccounts (consume Dashboard bootstrap cache)
      → analytics render when trades+accounts+profile ready
      → deferredSectionsReady (idle) → charts/reports/Pro card
      → copy groups ON DEMAND only
  → Navbar
      → badges from Session cache (no duplicate REST when Session ON)
      → notification Realtime (deferrable, non-blocking)
      → avatar lazy load
```

**Blocking:** Auth, profile slice, Dashboard RPC seed for trades/accounts  
**Essential non-blocking:** Session RPC completion, Realtime, avatar bytes  
**Deferrable:** Copy trading, getting-started signals, secondary route prefetch, deferred dashboard sections  
**Removed from cold path:** Copy-trading on idle dashboard mount; Dashboard warm on marketing routes for logged-in browsers

---

## Step 5 — Copy-trading correction

**Root cause:** `useCopyTradingGroups` enabled after `deferredSectionsReady` (~1.2s idle) still ran automatically on every Pro dashboard cold start, with sequential `copy_trading_groups` → `copy_trading_group_accounts`.

**Fix:**
1. Load only when user opens account picker / filter sheet **or** saved filter is `copygroup:{id}`.
2. Single nested Supabase select (one round trip when groups exist).

---

## Step 6 — Session / Dashboard overlap (measurement only)

| Field | Session RPC | Dashboard RPC | Notes |
|-------|-------------|---------------|-------|
| Accounts | `accounts_summary` (5 fields) | Full `accounts` rows | **Duplicate scan** when both RPCs ON; different shape/consumers |
| Profile | `session_profile` + `viewer` | — | Dashboard does not repeat profile |
| Badges | `badges.*` | — | Navbar uses Session cache |
| Trades | — | `trade_window` + metrics | Dashboard-owned |

**Decision:** Keep independent RPCs (independent failure preserved). Option B (`p_omit_accounts` when Session cache warm) documented for future flag — **not implemented** in this phase.

---

## Step 7–8 — Dashboard critical path & idle

- Shell renders after cached profile or Session profile slice
- Analytics blocked only on trades/accounts/profile (unchanged)
- Copy trading no longer hits network while idle on dashboard
- No polling added; persistent Realtime WS expected

---

## Files changed

| File | Change |
|------|--------|
| `lib/appWarmPaths.ts` | Marketing/auth path gating for Dashboard warm + Realtime |
| `lib/UserProfileProvider.tsx` | Gate warm/realtime; SIGNED_IN still starts Dashboard parallel |
| `lib/copyTradingGroups.ts` | Nested select — one query |
| `app/(app)/dashboard/page.tsx` | On-demand copy groups |
| `app/components/dashboard/DashboardFilters.tsx` | `onRequestCopyGroups` |
| `app/components/TradeAccountPicker.tsx` | `onPickerOpen` |
| `app/components/TradeFilterBar.tsx` | Pass-through |
| `app/components/platform/native/NativeIosDashboardActionBar.tsx` | Pass-through |
| `app/components/FreePlanAccountSlotShell.tsx` | Skip accounts/trades load when Session shows ≤3 accounts |
| `lib/coldStart.test.ts` | Wiring tests |
| `docs/backend-v2/PHASE_COLD_START_OPTIMIZATION.md` | This doc |

---

## Validation

```bash
npm run test:backend-v2   # includes coldStart.test.ts
npm run build
```

---

## Remaining bottlenecks

1. Session + Dashboard RPC latency (~2.4s combined server-wait in HAR 8) — Phase A migration not applied to production
2. Auth token exchange ~731ms — Supabase Auth, not app-table
3. Server-side landing Suspense queries (anonymous `/` RSC) — intentional marketing content
4. Full trade history background fetch after Dashboard window

---

## Confirmations

- **Production:** no migrations; client-only optimizations
- **Untouched:** native-ios/, Auth semantics, RLS, FreePlan rules, Feed/Messages phases
- **Stopped after cold-start optimization**
