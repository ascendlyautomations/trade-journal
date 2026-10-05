-- Public Trade Detail / trades_public_read — safe copy-trade linkage + participating mode aggregate
-- (same aggregate as feed/profile `copy_trade_public_participating_account_modes_json`).

drop view if exists public.trades_public_read;

create view public.trades_public_read
with (security_invoker = true, security_barrier = true)
as
select
  id,
  user_id,
  created_at,
  date,
  trade_date,
  pnl,
  rr,
  points,
  contracts,
  session,
  ticker,
  direction,
  public_description,
  is_public,
  is_pinned,
  image_url,
  image_crop,
  image_display_mode,
  entry_time,
  exit_time,
  entry_price,
  exit_price,
  duration_seconds,
  duration_text,
  account_type,
  mode,
  trade_mode,
  trade_type,
  timeframe,
  market_condition,
  first_published_at,
  copy_trading_group_id,
  copied_account_ids,
  source_account_id,
  public.copy_trade_public_participating_account_modes_json(trades.*) as participating_account_modes
from public.trades
where coalesce(is_public, false) = true;

comment on view public.trades_public_read is
  'Non-owner read surface for is_public trades — excludes journal/psychology/import/broker columns. security_invoker; row access via trades RLS.';

grant select on public.trades_public_read to anon, authenticated;

revoke select on table public.trades from anon;

grant select (
  id,
  user_id,
  created_at,
  date,
  trade_date,
  pnl,
  rr,
  points,
  contracts,
  session,
  ticker,
  direction,
  public_description,
  is_public,
  is_pinned,
  image_url,
  image_crop,
  image_display_mode,
  entry_time,
  exit_time,
  entry_price,
  exit_price,
  duration_seconds,
  duration_text,
  account_type,
  mode,
  trade_mode,
  trade_type,
  timeframe,
  market_condition,
  first_published_at,
  copy_trading_group_id,
  copied_account_ids,
  source_account_id
) on table public.trades to anon;
