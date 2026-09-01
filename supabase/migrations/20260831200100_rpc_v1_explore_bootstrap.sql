-- Phase 2: Explore landing bootstrap — traders, rooms, social counts, following, activity meta.

create or replace function public.rpc_v1_explore_bootstrap(
  p_trader_limit int default 24,
  p_room_limit int default 12,
  p_trader_offset int default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_trader_limit int := greatest(least(coalesce(p_trader_limit, 24), 48), 1);
  v_room_limit int := greatest(least(coalesce(p_room_limit, 12), 50), 1);
  v_trader_offset int := greatest(coalesce(p_trader_offset, 0), 0);
  v_traders jsonb := '[]'::jsonb;
  v_rooms jsonb := '[]'::jsonb;
  v_social jsonb := '{}'::jsonb;
  v_following jsonb := '[]'::jsonb;
  v_activity jsonb := '{}'::jsonb;
  v_next_cursor text := null;
  v_profile_ids uuid[];
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(f.following_id::text order by f.following_id),
    '[]'::jsonb
  )
  into v_following
  from public.followers f
  where f.follower_id = v_uid;

  with trader_page as (
    select
      p.id,
      p.username,
      p.name,
      p.bio,
      p.avatar_url,
      p.trader_type,
      p.trading_style,
      p.primary_market,
      p.started_trading,
      p.is_private,
      p.created_at
    from public.profiles p
    where p.username is not null
      and trim(p.username) <> ''
      and coalesce(p.is_private, false) = false
      and p.id <> v_uid
      and not exists (
        select 1 from public.followers f
        where f.follower_id = v_uid
          and f.following_id = p.id
      )
    order by p.created_at desc
    offset v_trader_offset
    limit v_trader_limit + 1
  ),
  trimmed as (
    select * from trader_page
    limit v_trader_limit
  ),
  trader_meta as (
    select count(*) as cnt from trader_page
  )
  select
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', t.id,
            'username', t.username,
            'name', t.name,
            'bio', t.bio,
            'avatar_url', t.avatar_url,
            'trader_type', t.trader_type,
            'trading_style', t.trading_style,
            'primary_market', t.primary_market,
            'started_trading', t.started_trading,
            'is_private', coalesce(t.is_private, false),
            'created_at', to_char(t.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          )
          order by t.created_at desc
        )
        from trimmed t
      ),
      '[]'::jsonb
    ),
    case
      when (select cnt from trader_meta) > v_trader_limit
        then (v_trader_offset + v_trader_limit)::text
      else null
    end,
    coalesce((select array_agg(t.id) from trimmed t), '{}'::uuid[])
  into v_traders, v_next_cursor, v_profile_ids;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'name', r.name,
        'description', r.description,
        'slug', r.slug,
        'member_count', r.member_count,
        'image_url', r.image_url
      )
      order by r.member_count desc nulls last, r.name asc
    ),
    '[]'::jsonb
  )
  into v_rooms
  from (
    select
      pr.id,
      pr.name,
      pr.description,
      pr.slug,
      pr.member_count,
      rm.image_url
    from public.popular_trade_rooms(v_room_limit) pr
    left join public.rooms rm on rm.id = pr.id
  ) r;

  if coalesce(array_length(v_profile_ids, 1), 0) > 0 then
    select coalesce(
      jsonb_object_agg(
        sc.profile_id::text,
        jsonb_build_object(
          'followers', sc.followers_count,
          'following', sc.following_count
        )
      ),
      '{}'::jsonb
    )
    into v_social
    from public.explore_social_counts(v_profile_ids) sc;

    with summaries as (
      select
        m.user_id,
        m.trade_count,
        m.last_trade_at
      from public.explore_trade_meta_aggregates(1500) m
      where m.row_kind = 'summary'
        and m.user_id = any (v_profile_ids)
    )
    select coalesce(
      jsonb_object_agg(
        s.user_id::text,
        jsonb_build_object(
          'trade_count', s.trade_count,
          'last_trade_at', case
            when s.last_trade_at is null then null
            else to_char(s.last_trade_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          end
        )
      ),
      '{}'::jsonb
    )
    into v_activity
    from summaries s;
  end if;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'traders', v_traders,
      'rooms', v_rooms,
      'social_counts', v_social,
      'following_ids', v_following,
      'activity_meta', v_activity,
      'traders_next_cursor', v_next_cursor
    )
  );
end;
$$;

revoke all on function public.rpc_v1_explore_bootstrap(int, int, int) from public;
grant execute on function public.rpc_v1_explore_bootstrap(int, int, int) to authenticated;

comment on function public.rpc_v1_explore_bootstrap is
  'Phase 2 Explore bootstrap — discoverable traders, popular rooms, social counts, following ids, trade activity meta.';
