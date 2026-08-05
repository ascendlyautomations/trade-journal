-- Phase 3 Disk IO: keyset pagination for leaderboard trade scans.
-- Replaces deep OFFSET rescans with (created_at, user_id) seek.

create or replace function public.leaderboard_trade_rows_page(
  p_after_created_at timestamptz default null,
  p_after_user_id uuid default null,
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
    and coalesce(t.is_public, false) = true
    and (
      p_after_created_at is null
      or (t.created_at, t.user_id) > (p_after_created_at, p_after_user_id)
    )
  order by t.created_at asc, t.user_id asc
  limit greatest(least(coalesce(p_limit, 1000), 1000), 1);
$$;

comment on function public.leaderboard_trade_rows_page(timestamptz, uuid, int) is
  'Keyset-paginated minimal trade rows for leaderboard aggregation (public profiles + public trades).';

grant execute on function public.leaderboard_trade_rows_page(timestamptz, uuid, int) to anon;
grant execute on function public.leaderboard_trade_rows_page(timestamptz, uuid, int) to authenticated;
grant execute on function public.leaderboard_trade_rows_page(timestamptz, uuid, int) to service_role;

-- Keep legacy OFFSET RPC for any external callers; prefer _page in app code.
comment on function public.leaderboard_trade_rows(int, int) is
  'Legacy OFFSET pagination for leaderboard rows. Prefer leaderboard_trade_rows_page.';
