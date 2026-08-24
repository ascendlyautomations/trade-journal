# Backend V2 Phase 3 — Dashboard Bootstrap

**Status:** `rpc_v1_dashboard_bootstrap` live. Flag `backendV2.dashboard` defaults **OFF**.

## 1. Dashboard REST audit (auth done → Dashboard paint)

| Request | Table(s) | Caller | Owner | In Dashboard Bootstrap? |
|---------|----------|--------|-------|-------------------------|
| `accounts` SELECT (ACCOUNTS_SELECT) | accounts | `ensureAccountsLoaded` / warm | **Dashboard** | **Yes** |
| `trades` limit 120 then full history | trades | `ensureTradesLoaded` / dashboard | **Dashboard** | **Yes** (window 500 + meta; full history only if incomplete) |
| Session profile / badges / following / prefs | profiles, … | UserProfileProvider / Session RPC | **Session** | **No** — consume session cache |
| copy_trading_groups (+ accounts) | copy_* | `useCopyTradingGroups` (Pro) | Dashboard-adjacent | **Not yet** (Phase 3.1) |
| Getting Started checklist HEADs | posts, followers, rooms | GettingStartedProgressProvider | Onboarding | **No** |
| Early-access status | API | TraxsProForLifeCard | Early-access | **No** |
| Trading report notify | API POST | TradingReportsSection | Side-effect | **No** |
| KPIs / equity / streaks / insights | — | `useDashboardAnalytics` | Client from trades | Metrics/equity **seeded** by RPC; UI still recomputes on filter |

## 2. Ownership map

```
Dashboard page / warmAppDataCaches / ensureTrades|Accounts
        │  (flag ON only)
        ▼
loadDashboardBootstrapForUser   ← sole orchestrator (single-flight)
        │
        ├── DashboardRpcBootstrapRepository  ← sole network owner
        │         └── rpc_v1_dashboard_bootstrap
        └── (dev dual-run) DashboardRestBootstrapRepository
                └── seeds appDataCache (accounts + trades)
```

Session fields never appear in this RPC.

## 3. SQL

`supabase/migrations/20260819200000_rpc_v1_dashboard_bootstrap.sql`  
Applied remotely via Supabase MCP.

Payload: accounts, trade_window (≤500), trade_window_meta, metrics (all non-backtest), equity_points (sampled), payout_total, recent_trades.

**Account ID type:** Backend V2 canonical = **UUID** (`accounts.id`, `p_account_id`). `trades.account_id` is legacy **text**; RPC compares with `p_account_id::text` at that boundary only (see `20260820211500_rpc_v1_dashboard_bootstrap_account_id_boundary.sql`).

## 4–7. Contracts / repos / flag / dual-run

| Piece | Location |
|-------|----------|
| Contracts | `lib/backendV2/contracts.ts` + iOS `DashboardBootstrapV1` |
| Repos | `dashboardBootstrapRepository.ts` |
| Cache / flight | `dashboardBootstrapCache.ts`, `dashboardBootstrapSingleFlight.ts` |
| Flag | `backendV2.dashboard` / `NEXT_PUBLIC_BACKEND_V2_DASHBOARD` |
| Dual-run | `NEXT_PUBLIC_BACKEND_V2_DUAL_RUN=1` in development |
| Wire | `appDataCache.ensure*` + `warmAppDataCaches` when flag ON |

## 10. Request counts (Dashboard-owned)

| | Flag OFF (before) | Flag ON (after) |
|--|-------------------|-----------------|
| accounts REST | 1 | **0** |
| trades REST (window) | 1 | **0** |
| trades REST (full history) | 0–1 if >120 | 0 if `history_complete`; else 1 continuation |
| Dashboard RPC | 0 | **1** |
| **Typical cold Dashboard trading fan-out** | **2–3** | **1** |

Copy-groups / checklist / early-access unchanged (not Dashboard bootstrap owned).

## Enable (dev)

```bash
# .env.local
NEXT_PUBLIC_BACKEND_V2_DASHBOARD=1
# optional dual-run:
NEXT_PUBLIC_BACKEND_V2_DUAL_RUN=1
```

Or `localStorage.setItem("backendV2.dashboard", "1")` then reload.
