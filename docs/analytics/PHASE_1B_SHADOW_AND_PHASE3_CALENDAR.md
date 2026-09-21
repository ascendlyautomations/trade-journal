# Phase 1B shadow analytics & Phase 3 calendar prep

Phase 1B adds `trade_daily_stats` and **normal** `analytics_calendar_day` semantics. Production Calendar/Dashboard/Profile/Reports are **unchanged**.

## Normal vs prop-firm / legacy trading day

| Concept | Function / code | Monday 7:30 PM ET |
|--------|------------------|-------------------|
| **Normal analytics calendar day** | SQL `analytics_calendar_day`, TS `lib/analytics/analyticsCalendarDay.ts` | **Monday** |
| **Legacy 18:00 ET trading day** | SQL `analytics_legacy_trading_day_key`, TS `getTradingDayKey` | **Tuesday** |
| **Prop-firm rules** | `lib/propfirmMetrics.ts`, native `PropFirmTradingDay` / `TradingCalendarDay.swift` | Unchanged in Phase 1B |

## Phase 3 — Calendar code to replace (do not switch in 1B)

| Surface | Location |
|---------|----------|
| Web calendar day filter | `app/calendar/page.tsx` — `getTradingDayKey(resolved)` |
| Web trading day helper | `lib/formatDate.ts` — `getTradingDayKey` |
| Web dashboard date keys | `lib/dashboardTradeDate.ts` |
| Prop-firm analytics day | `lib/propfirmMetrics.ts` |
| Native calendar | `native-ios/.../TradingCalendarDay.swift` |
| Native calendar VM | `native-ios/.../CalendarViewModel.swift` |
| Calendar tests (18:00) | `native-ios/.../CalendarExperienceTests.swift` |

Phase 3 should move **owner calendar display** to `analytics_calendar_day` while leaving prop-firm session logic on separate helpers.

## Shadow validation (after migration apply)

- `rpc_v1_analytics_daily_range_bootstrap(start, end, account_id?, mode?)` — owner read of daily rows + summary.
- `rpc_v1_analytics_shadow_compare_range(...)` — aggregate vs raw (normal calendar) vs raw (legacy trading day); labels date-semantics mismatches.

## Backfill

Run repeatedly until zero:

```sql
select public.backfill_trade_daily_stats_batch(50);
```

Or per user (service role):

```sql
select public.rebuild_trade_daily_stats_for_user('<user_id>');
```

## Bulk import (Phase 1C note)

Row triggers update aggregates inside the same DB transaction (no extra network). Optional optimization: `SET LOCAL app.skip_trade_daily_stats = 'on'` during mass import, then `rebuild_trade_daily_stats_for_user`.
