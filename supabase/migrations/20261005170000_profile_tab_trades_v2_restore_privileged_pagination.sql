-- Profile Trades V2 — fix 42501 on public.trades for authenticated callers.
--
-- Root cause: rpc_v1_profile_tab_trades_v2 (SECURITY INVOKER) paginates via
-- security_invoker trades_public_read. After 20261005160000 the view referenced
-- source_account_id (no authenticated column grant) and
-- copy_trade_public_participating_account_modes_json(trades.*) (requires journal
-- columns the authenticated role must not hold). Any invoker scan of the view fails.
--
-- Fix: invoker-safe trades_public_read projection + SECURITY DEFINER pagination
-- (same boundary as profile_visible_trade_rows).

-- ---------------------------------------------------------------------------
-- participating_account_modes for trades_public_read without trades.* (invoker-safe)
-- ---------------------------------------------------------------------------

create or replace function public.copy_trade_public_participating_account_modes_by_trade_id(
  p_trade_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.copy_trade_public_participating_account_modes_json(t)
  from public.trades t
  where t.id = p_trade_id
    and coalesce(t.is_public, false) = true;
$$;

comment on function public.copy_trade_public_participating_account_modes_by_trade_id(uuid) is
  'trades_public_read — copy-trade mode aggregate without invoker reading trades.*';

revoke all on function public.copy_trade_public_participating_account_modes_by_trade_id(uuid) from public;
grant execute on function public.copy_trade_public_participating_account_modes_by_trade_id(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- trades_public_read — restore column-safe invoker reads
-- ---------------------------------------------------------------------------

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
  public.copy_trade_public_participating_account_modes_by_trade_id(trades.id) as participating_account_modes
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

revoke select on table public.trades from authenticated;

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
) on table public.trades to authenticated;

-- ---------------------------------------------------------------------------
-- Profile Trades V2 pagination — server-side read boundary (no invoker trades scan)
-- ---------------------------------------------------------------------------

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
    select t.id, t.created_at
    from public.trades t
    where t.user_id = auth.uid()
      and coalesce(t.is_public, false) = true
      and (
        p_cursor_ts is null
        or (t.created_at, t.id) < (p_cursor_ts, p_cursor_id)
      )
    order by t.created_at desc, t.id desc
    limit v_fetch;
    return;
  end if;

  return query
  select t.id, t.created_at
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
      or (t.created_at, t.id) < (p_cursor_ts, p_cursor_id)
    )
  order by t.created_at desc, t.id desc
  limit v_fetch;
end;
$$;

comment on function public.profile_tab_trades_v2_page(uuid, timestamptz, uuid, integer) is
  'Profile Trades V2 cursor page (id, created_at). SECURITY DEFINER; mirrors trades RLS without granting table SELECT.';

revoke all on function public.profile_tab_trades_v2_page(uuid, timestamptz, uuid, integer) from public;
grant execute on function public.profile_tab_trades_v2_page(uuid, timestamptz, uuid, integer) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- rpc_v1_profile_tab_trades_v2 — paginate via profile_tab_trades_v2_page
-- ---------------------------------------------------------------------------

create or replace function public.rpc_v1_profile_tab_trades_v2(
  p_profile_id uuid,
  p_limit integer default 24,
  p_cursor text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_viewer uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 24), 1), 100);
  v_cursor_ts timestamptz;
  v_cursor_id uuid;
  v_can_view boolean := false;
  v_items jsonb := '[]'::jsonb;
  v_has_more boolean := false;
  v_next_cursor text := null;
  v_engagement jsonb := '{}'::jsonb;
begin
  if p_profile_id is null then
    raise exception 'invalid_profile_id' using errcode = '22023';
  end if;

  select (
    v_viewer = p_profile_id
    or coalesce(p.is_private, false) = false
    or exists (
      select 1 from public.followers f
      where f.follower_id = v_viewer and f.following_id = p_profile_id
    )
  ) into v_can_view
  from public.profiles p
  where p.id = p_profile_id;

  if not coalesce(v_can_view, false) then
    return jsonb_build_object(
      'meta', jsonb_build_object(
        'contract_version', 'v2',
        'found', false,
        'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'viewer_id', v_viewer
      ),
      'data', jsonb_build_object(
        'tab', 'trades',
        'items', '[]'::jsonb,
        'engagement', '{}'::jsonb,
        'next_cursor', null
      )
    );
  end if;

  if p_cursor is not null and trim(p_cursor) <> '' then
    v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
    v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
  end if;

  with page as (
    select p.id, p.created_at
    from public.profile_tab_trades_v2_page(
      p_profile_id,
      v_cursor_ts,
      v_cursor_id,
      v_limit + 1
    ) p
  ),
  trimmed as (
    select * from page limit v_limit
  )
  select
    coalesce(
      jsonb_agg(
        public.profile_visible_trade_tab_item_v2(tr.id)
        order by tr.created_at desc, tr.id desc
      ),
      '[]'::jsonb
    ),
    (select count(*) > v_limit from page)
  into v_items, v_has_more
  from trimmed tr;

  if v_has_more then
    select (elem->>'created_at') || '|' || (elem->>'id')
    into v_next_cursor
    from (
      select elem
      from jsonb_array_elements(v_items) as elem
      order by (elem->>'created_at') asc, (elem->>'id') asc
      limit 1
    ) sub;
  end if;

  with trade_ids as (
    select (elem->>'id')::uuid as id
    from jsonb_array_elements(v_items) elem
    where elem ? 'id'
  )
  select coalesce(jsonb_object_agg(
    ti.id::text,
    jsonb_build_object(
      'like_count', coalesce(lc.like_count, 0),
      'liked_by_me', coalesce(lc.liked_by_me, false),
      'comment_count', coalesce(cc.comment_count, 0)
    )
  ), '{}'::jsonb)
  into v_engagement
  from trade_ids ti
  left join lateral (
    select count(*)::integer as like_count,
      bool_or(v_viewer is not null and tl.user_id = v_viewer) as liked_by_me
    from public.trade_likes tl where tl.trade_id = ti.id
  ) lc on true
  left join lateral (
    select count(*)::integer as comment_count
    from public.trade_comments tc where tc.trade_id = ti.id
  ) cc on true;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v2',
      'found', true,
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_viewer
    ),
    'data', jsonb_build_object(
      'tab', 'trades',
      'items', v_items,
      'engagement', v_engagement,
      'next_cursor', v_next_cursor
    )
  );
end;
$$;
