# Canonical metric ownership map

## `trade_daily_stats` (additive / composable)

Safe to sum across days/accounts/modes (with correct filters):

| Ingredient | Composed metrics |
|------------|------------------|
| `trade_count`, win/loss/breakeven counts | win rate, profit per trade |
| `net_pnl`, `gross_profit`, `gross_loss` | profit factor, average winner/loser |
| `long_*`, `short_*` | directional breakdown |
| `sum_rr`, `rr_count` | average RR |
| `sum_hold_seconds`, `hold_count` | average hold |
| `largest_win`, `largest_loss` (per day) | range largest win/loss via MAX/MIN across days |

**Not in daily stats:** win/loss streaks, max drawdown, trade sequence equity.

## Chronological trade read model (raw / sequence)

Source: `trades` ordered by `analytics_realized_sort_ts` → trade id.

- Exact max drawdown (running peak/trough)
- Win/loss streaks
- Trade-by-trade equity curve
- Order-dependent psychology sequencing

## Payout domain

- `account_payout_*`, payout entries, cycles
- Dashboard “total payouts” — not from `trade_daily_stats`

## Prop-firm domain

- `analytics_legacy_trading_day_key` / `getTradingDayKey` / native `TradingCalendarDay`
- Consistency %, winning-day counts, payout eligibility, daily loss vs session rules
- **Independent** from normal `calendar_day`

## Psychology domain

- Daily check-ins, coach facts, correlation — not daily trade aggregates

## Production UI today (legacy)

Dashboard / Calendar / Profile Statistics / Reports still use legacy paths until explicit cutover phases.
