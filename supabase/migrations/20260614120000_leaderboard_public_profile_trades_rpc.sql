-- Leaderboard: aggregate stats from all trades for users with public profiles.
-- Does not expose trade details (symbol, notes, images, etc.) — only fields needed
-- for client-side P&L aggregation. Bypasses trades RLS via SECURITY DEFINER.

create or replace function public.leaderboard_trade_rows(
  p_offset int default 0,
  p_limit int default 1000
)
returns table (
  user_id uuid,
  pnl numeric,
  rr numeric,
  created_at timestamptz,
  account_type text,
  mode text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    t.user_id,
    t.pnl,
    t.rr,
    t.created_at,
    t.account_type::text,
    t.mode::text
  from public.trades t
  inner join public.profiles p on p.id = t.user_id
  where coalesce(p.is_private, false) = false
  order by t.created_at asc
  offset greatest(p_offset, 0)
  limit greatest(least(p_limit, 1000), 1);
$$;

comment on function public.leaderboard_trade_rows(int, int) is
  'Paginated minimal trade rows for leaderboard aggregation (public profiles only).';

grant execute on function public.leaderboard_trade_rows(int, int) to anon;
grant execute on function public.leaderboard_trade_rows(int, int) to authenticated;
