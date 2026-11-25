-- Private profiles: discoverable in explore; public header stats without trade rows for locked viewers.

-- Aggregate-only stats (no trade rows) for visitors who cannot view private content.
create or replace function public.profile_public_header_stats(p_profile_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_payout_total numeric := 0;
  v_stats jsonb;
begin
  select coalesce(sum(coalesce(a.value_numeric, 0)), 0)::numeric
  into v_payout_total
  from public.achievements a
  where a.user_id = p_profile_id
    and lower(trim(coalesce(a.achievement_type, ''))) like '%payout%';

  with eligible as (
    select t.pnl, t.rr
    from public.trades t
    where t.user_id = p_profile_id
      and t.is_public is true
      and coalesce(t.mode, '') <> 'backtest'
      and coalesce(t.account_type, '') <> 'backtest'
  )
  select jsonb_build_object(
    'total_trades', count(*),
    'wins', count(*) filter (where coalesce(pnl, 0) > 0),
    'total_pnl', coalesce(sum(pnl), 0),
    'profit_factor', case
      when coalesce(sum(pnl) filter (where coalesce(pnl, 0) < 0), 0) < 0
      then (
        coalesce(sum(pnl) filter (where coalesce(pnl, 0) > 0), 0)::numeric
        / abs(coalesce(sum(pnl) filter (where coalesce(pnl, 0) < 0), 0)::numeric)
      )
      else null
    end,
    'average_rr', case
      when count(*) filter (where rr is not null) > 0
      then avg(rr::numeric) filter (where rr is not null)
      else null
    end,
    'payout_total', v_payout_total
  )
  into v_stats
  from eligible;

  return coalesce(v_stats, jsonb_build_object('payout_total', v_payout_total));
end;
$$;

comment on function public.profile_public_header_stats(uuid) is
  'Aggregate public-trade summary for profile header when viewer cannot access private content rows.';

grant execute on function public.profile_public_header_stats(uuid) to authenticated, anon;

-- rpc_v1_profile_bootstrap: full public_stats for locked viewers (not payout-only).
do $patch$
declare
  src text;
  updated text;
begin
  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_profile_bootstrap'
    and pg_get_function_identity_arguments(p.oid) =
      'p_identifier text, p_initial_tab text, p_limit integer, p_cursor text';

  if src is null then
    raise exception 'rpc_v1_profile_bootstrap was not found';
  end if;

  updated := replace(
    src,
    $old$  else
    v_public_stats := jsonb_build_object('payout_total', v_payout_total);
  end if;$old$,
    $new$  else
    v_public_stats := public.profile_public_header_stats(v_profile_id);
  end if;$new$
  );

  if updated = src and position('profile_public_header_stats' in src) = 0 then
    raise exception 'rpc_v1_profile_bootstrap locked-viewer public_stats branch was not found';
  end if;

  if updated <> src then
    execute updated;
  end if;
end;
$patch$;

-- Explore bootstrap: include private accounts in traders and suggested_traders lists.
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
  v_suggested_limit int := 12;
  v_traders jsonb := '[]'::jsonb;
  v_suggested_traders jsonb := '[]'::jsonb;
  v_rooms jsonb := '[]'::jsonb;
  v_social jsonb := '{}'::jsonb;
  v_following jsonb := '[]'::jsonb;
  v_activity jsonb := '{}'::jsonb;
  v_next_cursor text := null;
  v_profile_ids uuid[];
  v_suggested_ids uuid[] := '{}'::uuid[];
begin
  if v_uid is null then
    v_following := '[]'::jsonb;
  else
    select coalesce(
      jsonb_agg(f.following_id::text order by f.following_id),
      '[]'::jsonb
    )
    into v_following
    from public.followers f
    where f.follower_id = v_uid;
  end if;

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
      and (v_uid is null or p.id <> v_uid)
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

  if v_trader_offset = 0 then
    with suggested as (
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
        and p.avatar_url is not null
        and length(trim(p.avatar_url)) > 0
        and (v_uid is null or p.id <> v_uid)
        and not exists (
          select 1 from public.followers f
          where f.follower_id = v_uid
            and f.following_id = p.id
        )
      order by p.created_at desc
      limit v_suggested_limit
    )
    select
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', s.id,
              'username', s.username,
              'name', s.name,
              'bio', s.bio,
              'avatar_url', s.avatar_url,
              'trader_type', s.trader_type,
              'trading_style', s.trading_style,
              'primary_market', s.primary_market,
              'started_trading', s.started_trading,
              'is_private', coalesce(s.is_private, false),
              'created_at', to_char(s.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
            )
            order by s.created_at desc
          )
          from suggested s
        ),
        '[]'::jsonb
      ),
      coalesce((select array_agg(s.id) from suggested s), '{}'::uuid[])
    into v_suggested_traders, v_suggested_ids;
  end if;

  v_profile_ids := (
    select coalesce(array_agg(distinct x), '{}'::uuid[])
    from unnest(coalesce(v_profile_ids, '{}'::uuid[]) || coalesce(v_suggested_ids, '{}'::uuid[])) as x
  );

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
      'suggested_traders', v_suggested_traders,
      'rooms', v_rooms,
      'social_counts', v_social,
      'following_ids', v_following,
      'activity_meta', v_activity,
      'traders_next_cursor', v_next_cursor
    )
  );
end;
$$;

comment on function public.rpc_v1_explore_bootstrap(int, int, int) is
  'Explore bootstrap — directory traders (paginated), suggested_traders with avatars (offset 0), rooms, social, following, activity meta. Private profiles are discoverable.';