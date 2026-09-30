-- Clear Supabase "Security Definer View" lint on trades_public_read.
--
-- security_invoker runs underlying trades RLS as the caller, so non-owner row
-- visibility must come from explicit policies (not view-owner bypass).
-- trades_public_read still projects only the public/social column subset.
--
-- We do NOT restore unconstrained is_public-only reads: profile-gated discovery
-- matches 20260620120000_private_profile_public_discovery.

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
  copied_account_ids
from public.trades
where coalesce(is_public, false) = true;

comment on view public.trades_public_read is
  'Non-owner read surface for is_public trades — excludes journal/psychology/import/broker columns. security_invoker; row access via trades RLS.';

grant select on public.trades_public_read to anon, authenticated;

-- Invoker scans require matching row policies on public.trades (dropped in 202609292210).
drop policy if exists "trades_select_public" on public.trades;

create policy "trades_select_public"
  on public.trades
  for select
  to anon, authenticated
  using (
    coalesce(is_public, false) = true
    and exists (
      select 1
      from public.profiles p
      where p.id = trades.user_id
        and coalesce(p.is_private, false) = false
    )
  );

comment on policy "trades_select_public" on public.trades is
  'Public trades from public profiles — enables security_invoker trades_public_read; prefer the view for column-safe reads.';

-- Defense in depth: anon may only SELECT social-safe columns on public.trades
-- (table-level SELECT would bypass column REVOKE).
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
  copied_account_ids
) on table public.trades to anon;
