# Dashboard V3 contract

## RPC

`rpc_v1_analytics_dashboard_bootstrap_v3()` — owner-only (`auth.uid()`), no arguments.

## Bounded history strategy

The RPC does **not** ship raw trades or unbounded `trade_daily_stats` daily rows.

**Bootstrap (`rpc_v1_analytics_dashboard_bootstrap_v3`):**

- `presets`: five **all-accounts** full bundles (`metrics` + `equity` + `distributions` + `insights`).
- `account_preset_metrics`: one row per account × five presets — **metrics only** (from `trade_daily_stats`) for instant account KPI filters.
- `accounts`: single canonical account list (not duplicated per preset).
- **No** `trade_window`, **no** daily row array (`dailyRows` log is always 0 — preset summaries, not Calendar-style days).

**Account charts (`rpc_v1_analytics_dashboard_account_charts_v3(p_account_id)`):**

- Five preset chart bundles for one account (equity/distributions/insights).
- Fetched on account filter change; cached in memory keyed by `(account_id, revision)`.

All Time totals remain exact via full-range daily aggregation on the server — not a rolling cap.

Bootstrap payload scales ~`5 full bundles + N×5 metrics slices + accounts` (not `(1+N)×5` full bundles).

## Date semantics

Presets use **America/New_York civil** calendar days (`analytics_calendar_day`), not device timezone and not 18:00 rollover.

## Equity normalization

Equity and max drawdown use **`analytics_realized_sort_ts`** (intentional normalization vs legacy dashboard `created_at` ordering).

## iOS flag

`backendV2.dashboardAnalyticsV3` — default **OFF**; not in `productionShippedFlags`.

Legacy `rpc_v1_dashboard_bootstrap` unchanged for rollback.
