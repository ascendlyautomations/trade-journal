# Backend V2 Phase 3.1 — Dashboard Bootstrap local enable

## Enabled

`.env.local`:

```
NEXT_PUBLIC_BACKEND_V2_DASHBOARD=1
```

(`NEXT_PUBLIC_BACKEND_V2_DUAL_RUN` left commented — enable only when comparing REST vs RPC in console.)

**Required:** restart `npm run dev` + hard refresh (Next inlines `NEXT_PUBLIC_*` at compile).

## Expected Network (authenticated → Dashboard)

| Request | Expected |
|---------|----------|
| `POST …/rpc/rpc_v1_session_bootstrap` | 1× (if session flag ON) |
| `POST …/rpc/rpc_v1_dashboard_bootstrap` | **1×** |
| `GET …/rest/v1/accounts` (bootstrap) | **0** |
| `GET …/rest/v1/trades` window (bootstrap) | **0** |
| `GET …/rest/v1/trades` full history | Only if `trade_window_meta.history_complete === false` (>500 trades) |
| Copy groups / checklist / early-access | May remain (not Dashboard-bootstrap owned) |

With dual-run `=1`, REST accounts+trades **will** appear again (intentional compare) — keep dual-run off for clean HAR.

## Mutations (no re-bootstrap)

- Create/edit: `InputTradeForm` → `upsertTradeInCache`
- Delete: `deleteTrade` → `removeTradeFromCache`
- Dashboard reads cache via `useCachedTrades` / `useCachedAccounts`
- `loadDashboardBootstrapForUser` must not run again until logout / invalidate

## Verify in DevTools

1. Filter Network: `rpc_v1_dashboard_bootstrap`
2. Console (optional dual-run): `[backendV2.dashboard] dual-run`
3. Confirm UI parity vs prior REST Dashboard
