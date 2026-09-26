-- Profile trades pagination decode fix.
-- rpc_v1_profile_tab_trades dropped meta.server_time, which BootstrapMetaV1 requires.
-- The first page comes from rpc_v1_profile_bootstrap (still has server_time).
-- The next page calls this RPC, gets HTTP 200, and the client throws
-- BackendV2RPCError.decode (NSError code 3).

create or replace function public.rpc_v1_profile_tab_trades(
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
  v_server_time text := to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
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
        'contract_version', 'v1',
        'found', false,
        'server_time', v_server_time,
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
    begin
      v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
      v_cursor_id := nullif(split_part(p_cursor, '|', 2), '')::uuid;
    exception
      when invalid_datetime_format or invalid_text_representation then
        -- A bad cursor is the end of the list, not a failed page.
        v_cursor_ts := null;
        v_cursor_id := null;
        v_has_more := false;
        return jsonb_build_object(
          'meta', jsonb_build_object(
            'contract_version', 'v1',
            'found', true,
            'server_time', v_server_time,
            'viewer_id', v_viewer
          ),
          'data', jsonb_build_object(
            'tab', 'trades',
            'items', '[]'::jsonb,
            'engagement', '{}'::jsonb,
            'next_cursor', null
          )
        );
    end;
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
    coalesce(jsonb_agg(to_jsonb(tr) order by tr.created_at desc, tr.id desc), '[]'::jsonb),
    (select count(*) > v_limit from page)
  into v_items, v_has_more
  from trimmed tr;

  if v_has_more then
    select (
      to_char(tr.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      || '|' || tr.id::text
    )
    into v_next_cursor
    from (
      select t.created_at, t.id
      from public.trades t
      where t.user_id = p_profile_id
        and t.is_public is true
        and (
          v_cursor_ts is null
          or (t.created_at, t.id) < (v_cursor_ts, v_cursor_id)
        )
      order by t.created_at desc, t.id desc
      limit v_limit
    ) tr
    order by tr.created_at asc, tr.id asc
    limit 1;
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
      'contract_version', 'v1',
      'found', true,
      'server_time', v_server_time,
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
