-- Profile Trades V2 page — column 2 must be timestamptz.
--
-- rpc_v1_profile_tab_trades_v2 calls profile_tab_trades_v2_page, which
-- RETURNS TABLE (id uuid, created_at timestamptz) but selected trades.created_at
-- (timestamp without time zone). That is SQLSTATE 42804 on column 2.
--
-- trades.created_at stores the UTC wall clock. Interpret it as UTC and return
-- timestamptz so the cursor keeps the same absolute instant. Do not change the
-- declared return type, grants, or the 42501 pagination boundary.

create or replace function public.profile_tab_trades_v2_page(
  p_profile_id uuid,
  p_cursor_ts timestamptz,
  p_cursor_id uuid,
  p_fetch_limit integer
)
returns table(id uuid, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_fetch integer := least(greatest(coalesce(p_fetch_limit, 1), 1), 101);
begin
  if p_profile_id is null or not public.profile_viewer_can_view_trades(p_profile_id) then
    return;
  end if;

  if auth.uid() = p_profile_id then
    return query
    select t.id, (t.created_at AT TIME ZONE 'UTC')
    from public.trades t
    where t.user_id = auth.uid()
      and coalesce(t.is_public, false) = true
      and (
        p_cursor_ts is null
        or ((t.created_at AT TIME ZONE 'UTC'), t.id) < (p_cursor_ts, p_cursor_id)
      )
    order by t.created_at desc, t.id desc
    limit v_fetch;
    return;
  end if;

  return query
  select t.id, (t.created_at AT TIME ZONE 'UTC')
  from public.trades t
  where t.user_id = p_profile_id
    and coalesce(t.is_public, false) = true
    and not public.viewer_has_block_with(t.user_id)
    and public.profile_is_visible_to_viewer(t.user_id)
    and (
      exists (
        select 1
        from public.profiles p
        where p.id = t.user_id
          and coalesce(p.is_private, false) = false
      )
      or exists (
        select 1
        from public.followers f
        where f.following_id = t.user_id
          and f.follower_id = auth.uid()
      )
    )
    and (
      p_cursor_ts is null
      or ((t.created_at AT TIME ZONE 'UTC'), t.id) < (p_cursor_ts, p_cursor_id)
    )
  order by t.created_at desc, t.id desc
  limit v_fetch;
end;
$$;

comment on function public.profile_tab_trades_v2_page(uuid, timestamptz, uuid, integer) is
  'Profile Trades V2 cursor page (id, created_at timestamptz). created_at is trades.created_at read as UTC. SECURITY DEFINER; mirrors trades RLS without granting table SELECT.';
