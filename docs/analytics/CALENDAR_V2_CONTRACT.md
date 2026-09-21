# Calendar V2 data contract (design only — not implemented)

## Semantics

- **Normal calendar day** = `analytics_calendar_day` (ET civil date, entry → exit → `created_at` UTC, **no** 18:00 rollover).
- **Prop-firm trading day** = existing prop-firm/session rules — **not** stored in `trade_daily_stats.calendar_day`.

Example: Monday 7:30 PM ET → **Monday** on Calendar V2.

## Read path (target)

```
Open month
  → local cache keyed by (user_id, month, account_filter, mode_filter, revision)
  → rpc_v1_analytics_daily_range_bootstrap(month_start, month_end, account_id?, mode?)
  → render month grid (daily P&L, W/L/B counts, optional heat)
Tap day
  → TradeSummary list for that calendar day (existing trades list RPC / filter by normal day)
  → TradeDetail on row tap only
```

## Month boundaries

- Query `[first_day_of_month, last_day_of_month]` in **normal calendar** dates (ET semantics via server `analytics_calendar_day`).
- Week totals (if shown): sum daily rows whose `calendar_day` falls in ISO or Sun–Sat week per product choice (document in UI; server returns daily rows only).

## Filters

| Filter | Behavior |
|--------|----------|
| All accounts | `p_account_id := null` |
| Single account | UUID |
| Mode | `evaluation` / `funded` / `live` / `sim` / `backtest` / `unknown`; null = all except backtest (matches shadow RPC) |

Account **names/modes** come from existing session/account bootstrap — not duplicated inside analytics RPC.

## RPC: `rpc_v1_analytics_daily_range_bootstrap`

**Request:** `p_start`, `p_end`, optional `p_account_id`, optional `p_mode`.

**Response (bounded):**

- `revision`, `state_updated_at` from `user_analytics_state`
- `days[]`: per `(calendar_day, account_id, mode_effective)` composable ingredients
- `summary`: range rollup (same ingredients, composable derived metrics client-side)

**Not included:** raw trades, drawdown, streaks, prop-firm day, psychology.

## Day drill-down (trades)

- Filter owner trades where `analytics_calendar_day(entry, exit, created_at) = selected_day` (server-side in list RPC when Calendar V2 ships).
- Pagination: keyset on `analytics_realized_sort_ts` + trade id.
- Large days: page size ~25–50 summaries; detail lazy.

## Cache / revision

- Client stores last seen `revision` per user.
- On fetch, if `revision` unchanged and month cached → skip network (future GRDB).
- Any trade INSERT/UPDATE/DELETE affecting stats, account mode rebuild, or user rebuild → revision++.

## Out of scope for Calendar V2 RPC

- Profile public aggregates
- Prop-firm consistency / winning-day eligibility
- Exact equity curve / streaks
