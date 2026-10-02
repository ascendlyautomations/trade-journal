-- Retire legacy trade_limit_trigger + enforce_trade_limits() (pre–supabase/migrations drift on some environments).
--
-- That trigger enforced:
--   - 3 trades / rolling 24h (all rows; no backtest/imported exclusions)
--   - 1 public trade / rolling 24h  → stale vs current Free tier policy
--
-- Authoritative enforcement (when free_plan_limits_enforced() is true):
--   trades_enforce_free_plan_daily_limit  — 3 manual journal trades / UTC day (excludes backtest + imported)
--   posts_enforce_free_plan_daily_limit   — 3 posts / day; skips quota when trade_id already has a post
--   reels_enforce_free_plan_daily_limit   — 3 clips / day
-- Copy trading: N account rows = N trade inserts toward the manual trade cap; feed posts stay one per trade_id.

drop trigger if exists trade_limit_trigger on public.trades;

drop function if exists public.enforce_trade_limits();
