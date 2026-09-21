# Local analytical GRDB (Phase 5B–5D shadow)

## Account identity in SQLite

Postgres `trade_daily_stats` uses `(user_id, calendar_day, mode_effective, account_id)` with **NULLS NOT DISTINCT** for `account_id`.

SQLite treats each `NULL` as distinct in UNIQUE constraints, so we store a non-null `account_scope_key`:

| Meaning | `account_scope_key` |
|---------|---------------------|
| Row with `account_id` NULL | `__null_account__` |
| Row for account UUID | lowercased normalized UUID |

Query coverage uses `account_scope` `*` when `p_account_id` was null (all accounts in range).

## Shadow mode

Calendar V2 and Dashboard V3 UI remain authoritative on memory / JSON / network. GRDB ingest and shadow **read/parity** run on utility tasks; failures are logged in DEBUG only.

## Typed read APIs (Phase 5D)

All reads require `viewerID`. States: `available`, `stale(foundRevision:)`, `partial`, `missing`.

- `readCalendarRange(...)` — coverage union validation then daily rows → wire rows.
- `readDashboardSnapshot(requiredRevision:)` — all five aggregate presets + charts at exact revision (no mixing).
- `readDashboardAccountCharts(accountID:requiredRevision:)` — per-account chart bundles; stale bundles never reported as current.
- `readCalendarRangeForPresentation(...)` — best full-coverage local revision for Calendar UI (Phase 5E).

## Calendar GRDB-first (Phase 5E)

Flag: `backendV2.calendarAnalyticsGRDB` (`BACKEND_V2_CALENDAR_ANALYTICS_GRDB`). Debug default ON; Release OFF.

Read order: GRDB → JSON disk → network. Network path remains: RPC → UI + JSON save + GRDB shadow ingest (converged read-after-write deferred).

## Dashboard GRDB-first (Phase 5F)

Flag: `backendV2.dashboardAnalyticsGRDB` (`BACKEND_V2_DASHBOARD_ANALYTICS_GRDB`). Requires V3. Debug default ON; Release OFF.

Read order: GRDB complete snapshot → `DashboardAnalyticsDiskCache` → network bootstrap. Account charts: GRDB at dashboard revision → RPC.

## Dashboard tables (migration v2)

- `dashboard_preset_metrics` — server-composed preset KPI ingredients (`scope` aggregate|account).
- `dashboard_chart_bundle` — JSON blob per `(viewer, account_scope_key, preset)` for equity/distributions/insights.

Aggregate chart bundles use `account_scope_key = *`. Per-account charts use normalized account UUID keys.

`analytics_sync_state.server_revision` updates **monotonically** (`max(existing, incoming)`). Row-level `ingested_revision` records the revision the payload was fetched under.
