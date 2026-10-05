-- Profile Trades V2 — copy-action linkage for presentation grouping (public rows only).

create or replace function public.trade_summary_profile_copy_linkage_json(
  p_trade public.trades
)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select case
    when lower(trim(coalesce(p_trade.trade_mode, ''))) <> 'copy_traded' then '{}'::jsonb
    else jsonb_strip_nulls(
      jsonb_build_object(
        'account_id', nullif(trim(coalesce(p_trade.account_id, '')), ''),
        'source_account_id', nullif(trim(coalesce(p_trade.source_account_id::text, '')), ''),
        'copied_account_ids', case
          when p_trade.copied_account_ids is null or cardinality(p_trade.copied_account_ids) = 0 then null
          else to_jsonb(p_trade.copied_account_ids)
        end,
        'copy_trading_group_id', nullif(trim(coalesce(p_trade.copy_trading_group_id::text, '')), '')
      )
    )
  end;
$$;

comment on function public.trade_summary_profile_copy_linkage_json(public.trades) is
  'Public Profile Trades tab — copy-action linkage for client-side grouping (no private journal fields).';

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
    select t.*
    from public.trades t
    where t.user_id = p_profile_id
      and t.is_public is true
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
        public.trade_summary_json(tr, v_viewer)
          || public.trade_summary_profile_copy_linkage_json(tr)
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

revoke all on function public.trade_summary_profile_copy_linkage_json(public.trades) from public;
grant execute on function public.trade_summary_profile_copy_linkage_json(public.trades) to authenticated;
grant execute on function public.trade_summary_profile_copy_linkage_json(public.trades) to anon;
