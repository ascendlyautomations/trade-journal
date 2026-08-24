# Phase H1 — Prop Firm Bootstrap + Dashboard Payload Audit

## 1. Before ownership map

| Route | Entry | Data owner | Cache | Route-specific network (warm) |
|-------|-------|------------|-------|-------------------------------|
| **Dashboard** | `app/(app)/dashboard/page.tsx` | `appDataCache` via `rpc_v1_dashboard_bootstrap` (flag) or REST | `tradesByUser[userId]`, `accountsByUser[userId]`, `dashboardBootstrapCache` | 0 when cache warm |
| **Calendar** | `app/calendar/page.tsx` | Pure consumer of `appDataCache` | Same as Dashboard | **0** (reels only on day select) |
| **Trades** | `app/(app)/trades/page.tsx` | Pure consumer of `appDataCache` | Same as Dashboard | **1 bounded reels** query (~10 visible IDs) |
| **Prop Firm** | `app/(app)/analytics/propfirm/page.tsx` | Route-local React state (before H1) | None | **~5 requests**: accounts + N payout + achievements + trades |

Shared auth shell: `UserProfileProvider` → `warmAppDataCaches()` → `startCriticalDashboardWarm()`.

Feature flags (pre-H1): `backendV2.session`, `backendV2.dashboard` — `backendV2.calendar` reserved but unwired.

---

## 2. Why Calendar and Trades were already efficient

**Calendar**
- No mount-time Supabase calls; only `useCachedTrades({ fullHistory: true })` + `useCachedAccounts()`.
- Dashboard warm at auth populates `appDataCache` before navigation.
- `ensureTradesLoaded()` returns immediately on cache hit (`appDataCache.ts`).
- All P&L/grid math is client-side from in-memory trades.
- Documented consumer: `docs/backend-v2/PHASE4_75_OWNERSHIP_CLEANUP.md`.

**Trades**
- Same cache hooks; no accounts/trades refetch on warm nav.
- Reels: `displayedTrades.slice(0, visibleCount)` (default 10) → `fetchReelsByTradeIds()` with module-level single-flight Map keyed by sorted trade IDs (`lib/reels.ts`).

**No changes made** to Calendar/Trades loading architecture beyond regression tests.

---

## 3. Dashboard payload composition

**RPC:** `rpc_v1_dashboard_bootstrap(p_account_id, p_trade_limit default 500)`

**Sections (`data`):**

| Section | Used by web UI | Notes |
|---------|----------------|-------|
| `accounts` | Yes (via cache) | Seeded to `appDataCache` |
| `trade_window` | Yes | Up to 500 rows × 46 fields (`TRADES_APP_SELECT`); ~211 KB in HAR |
| `trade_window_meta` | Partially | Getting Started / history completeness |
| `metrics` | **No** | Server aggregates; UI recomputes via `useDashboardAnalytics` |
| `equity_points` | **No** | Charts recompute from trades client-side |
| `payout_total` | **No** | Tests only |
| `recent_trades` | **No** | Duplicate of `trade_window[0..4]` |

**Dominant bytes:** full trade rows (notes, psychology fields, confluences, etc.) × 500.

**UI sections consuming raw trades:** stats grid, charts, filters, recent trades list, gear validation — all via `useDashboardAnalytics` on filtered cached trades.

---

## 4. Dashboard index/SQL decisions (this phase)

**No Dashboard SQL changes applied.** One HAR sample is insufficient to lower `p_trade_limit` or trim columns.

**Documented safe reductions (pending benchmark):**
1. Remove `recent_trades` duplicate (~5 full rows) — highest confidence, no web consumer.
2. Omit `metrics` / `equity_points` for web-only contract variant — medium risk (iOS adapters reference them).
3. Lower `p_trade_limit` toward 120 — triggers `ensureFullTradesHistory` second fetch for heavy journals.

**Benchmark:** `scripts/benchmark-rpc-bootstrap.mjs` (10 warm runs, payload bytes). Run on staging before any SQL change.

---

## 5. Prop Firm request causes (before)

1. **Accounts** — required for initial paint; Prop Firm category filter.
2. **Payout cycles × F** — `fetchPayoutCycleHistoryByAccountIds` used `Promise.all` per funded account (N+1 HTTP pattern).
3. **Achievements** — batched `.in("account_id", ids)` but separate request.
4. **Trades** — lightweight select, separate request; refetched on account filter change.

No overlap with Dashboard cache (different fields, Prop-Firm-only scope).

---

## 6. Prop Firm before/after architecture

**Before:** 4–5 parallel REST requests; payout N+1; no cache; refetch achievements/trades on account switch.

**After (flag `NEXT_PUBLIC_BACKEND_V2_PROP_FIRM=1`):**
- Single `rpc_v1_prop_firm_bootstrap()` — set-based SQL, SECURITY INVOKER.
- Client: `propFirmBootstrapRepository` + cache + single-flight.
- Account filter switches filter cached bootstrap client-side (no network).
- Legacy fallback only on missing-RPC (`PGRST202` / `42883`); 5xx does not trigger fan-out.
- Legacy path improved: payout cycles use one `.in("account_id", ids)` query even when flag OFF.

---

## 7. RPC contract and security

**Function:** `public.rpc_v1_prop_firm_bootstrap()` → `jsonb`

**Response:**
```json
{
  "meta": { "contract_version": "v1", "server_time", "viewer_id" },
  "data": {
    "accounts": [...],
    "payout_cycles": [...],
    "achievements": [...],
    "trades": [...]
  }
}
```

**Security:**
- `SECURITY INVOKER` — RLS on `accounts`, `trades`, `achievements`, `account_payout_cycles`.
- Viewer from `(select auth.uid())`; no client-supplied user ID.
- `REVOKE ALL FROM PUBLIC`; `GRANT EXECUTE TO authenticated`.
- Explicit `search_path = public, pg_temp`.

---

## 8. Cache and invalidation

- Key: viewer `userId` (module singleton entry).
- Single-flight per user.
- Soft-stale revalidation after 5 minutes (background, non-blocking).
- Stale generation rejection via `PropFirmBootstrapStaleError`.
- Invalidated on: eval→funded conversion, funded account create, logout (`clearPropFirmBootstrapCache`).
- Local payout patch still updates React state immediately.

---

## 9–11. Request counts / payload / latency

| Surface | Before (typical, 2 funded accounts) | After (flag ON) |
|---------|-------------------------------------|-----------------|
| Prop Firm init | 5 HTTP | **1 RPC** |
| Prop Firm account switch | +2 HTTP (achievements + trades) | **0** (client filter) |
| Calendar warm | 0 | 0 (unchanged) |
| Trades warm | 0–1 reels | 0–1 reels (unchanged) |
| Dashboard | 1 RPC (~211 KB) | unchanged |

**Latency/payload benchmarks:** Run locally/staging:
```bash
node scripts/benchmark-rpc-bootstrap.mjs   # dashboard
# Add after migration apply:
# node scripts/benchmark-prop-firm-rpc.mjs
```

---

## 12. Tests

- `lib/phaseH1.routeOwnership.test.ts` — Calendar/Trades/Dashboard wiring
- `lib/backendV2/propFirmBootstrap.phaseH1.test.ts` — contract, cache, RPC compat, SQL security

---

## 13. Migration files

| File | Purpose |
|------|---------|
| `supabase/migrations/20260824120000_rpc_v1_prop_firm_bootstrap.sql` | Create RPC |
| `supabase/rollbacks/20260824120000_rpc_v1_prop_firm_bootstrap_rollback.sql` | Drop RPC |

**Not applied to production** in this phase.

---

## 14. Staging rollout

1. Apply migration on staging Supabase.
2. Set `NEXT_PUBLIC_BACKEND_V2_PROP_FIRM=1` for internal testers.
3. Verify Prop Firm page: 1 RPC in network tab; account switch无 extra requests.
4. Confirm missing-RPC fallback (pre-migration build) uses improved legacy set-based payout query only.
5. Benchmark dashboard payload before any dashboard SQL trim.

---

## 15. Files changed

- `supabase/migrations/20260824120000_rpc_v1_prop_firm_bootstrap.sql` (new)
- `supabase/rollbacks/20260824120000_rpc_v1_prop_firm_bootstrap_rollback.sql` (new)
- `lib/backendV2/propFirmBootstrap*.ts` (new)
- `lib/backendV2/propFirmRpcCompat.ts` (new)
- `lib/backendV2/flags.ts`, `lib/backendV2/versioning.ts`
- `lib/propfirmPayoutCycles.ts` — set-based legacy payout fetch
- `app/(app)/analytics/propfirm/page.tsx` — V2 wiring + fallback
- `lib/UserProfileProvider.tsx` — logout cache clear
- `lib/phaseH1.routeOwnership.test.ts` (new)
- `lib/backendV2/propFirmBootstrap.phaseH1.test.ts` (new)
- `docs/backend-v2/PHASE_H1_PROP_FIRM_DASHBOARD_AUDIT.md` (this file)
- `package.json` — test script entries

---

## Confirmations

- **`native-ios/` untouched**
- **No production SQL applied**
- **Calendar/Trades/Dashboard loading paths preserved**
- **No new Calendar or Trades bootstrap RPCs**
