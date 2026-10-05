-- Profile Trades V2 — restore authorized read boundary after copy-linkage RPC
-- regressed to SECURITY INVOKER + SELECT t.* FROM public.trades (42501 for authenticated).

-- ---------------------------------------------------------------------------
-- One TradeSummary item: viewer-safe summary + public copy-linkage (account_id,
-- source_account_id, copied_account_ids, copy_trading_group_id, account_mode).
-- Full trades row stays inside SECURITY DEFINER with the same visibility gate as
-- profile_visible_trade_summary; callers never need table SELECT on public.trades.
-- ---------------------------------------------------------------------------

create or replace function public.profile_visible_trade_tab_item_v2(p_trade_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_trade public.trades%rowtype;
begin
  select * into v_trade
  from public.trades t
  where t.id = p_trade_id;

  if v_trade.id is null then
    return null;
  end if;

  if auth.uid() is distinct from v_trade.user_id
     and not (
       coalesce(v_trade.is_public, false)
       and public.profile_viewer_can_view_trades(v_trade.user_id)
     )
  then
    return null;
  end if;

  return public.trade_summary_json(v_trade, auth.uid())
    || public.trade_summary_profile_copy_linkage_json(v_trade);
end;
$$;

comment on function public.profile_visible_trade_tab_item_v2(uuid) is
  'Profile Trades V2 tab item — TradeSummary + copy-linkage JSON for public/profile-visible trades only.';

revoke all on function public.profile_visible_trade_tab_item_v2(uuid) from public;
grant execute on function public.profile_visible_trade_tab_item_v2(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- rpc_v1_profile_tab_trades_v2 — paginate via trades_public_read; hydrate items
-- via profile_visible_trade_tab_item_v2 (no direct public.trades reads as caller).
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
    select t.id, t.created_at
    from public.trades_public_read t
    where t.user_id = p_profile_id
      and (
        v_cursor_ts is null
        or (t.created_at, t.id) < (v_cursor_ts, v_cursor_id)
      )
    order by t.created_at desc, t.id desc
    limit v_limit + 1
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
