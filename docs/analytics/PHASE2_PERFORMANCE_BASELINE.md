# Phase 2 performance baseline (tradetraxss-scale)

Recorded on production TradeTraxs (~116 trades owner, ~730 total).

| Scenario | Path | Execution (EXPLAIN ANALYZE) |
|----------|------|-----------------------------|
| 1Y range rollup | `trade_daily_stats` aggregate | ~**0.22 ms** |
| 1Y range rollup | `analytics_raw_normal_range_metrics` | ~**20.3 ms** |

At current scale, daily aggregates are ~**90×** faster than scanning raw trades for the same composable metrics.

**Payload:** shadow daily RPC returns daily rows + summary JSON (no raw trades) — suitable for Calendar month sync.

Phase 3+ should re-measure after Calendar wiring with client-visible RPC timing and row counts.
