-- Public trades remain readable (anon + authenticated) but owner-only journal
-- columns are not exposed via direct PostgREST SELECT on public.trades rows.
--
-- Owners keep full access through trades_select_own on public.trades.

drop policy if exists "trades_select_public" on public.trades;

drop view if exists public.trades_public_read;

create view public.trades_public_read
with (security_barrier = true)
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
  copied_account_ids
from public.trades
where coalesce(is_public, false) = true;

comment on view public.trades_public_read is
  'Non-owner read surface for is_public trades — excludes journal/psychology/import/broker columns.';

grant select on public.trades_public_read to anon, authenticated;
