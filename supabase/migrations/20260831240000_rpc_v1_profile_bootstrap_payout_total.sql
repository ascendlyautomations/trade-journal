-- Profile bootstrap: add payout_total to public_stats (sum of public payout achievements).

create or replace function public.rpc_v1_profile_bootstrap(
  p_identifier text,
  p_initial_tab text default 'trades',
  p_limit integer default 6,
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
  v_profile_id uuid;
  v_profile public.profiles%rowtype;
  v_limit integer := least(greatest(coalesce(p_limit, 6), 1), 24);
  v_tab text := lower(trim(coalesce(p_initial_tab, 'trades')));
  v_is_own boolean := false;
  v_is_following boolean := false;
  v_is_requested boolean := false;
  v_follows_you boolean := false;
  v_can_view boolean := false;
  v_followers_count integer := 0;
  v_following_count integer := 0;
  v_cursor_ts timestamptz;
  v_cursor_id uuid;
  v_trades jsonb := '[]'::jsonb;
  v_has_more boolean := false;
  v_next_cursor text := null;
  v_public_stats jsonb := null;
  v_section_counts jsonb;
  v_engagement jsonb := '{}'::jsonb;
  v_owned_room jsonb := null;
begin
  if p_identifier is null or trim(p_identifier) = '' then
    raise exception 'invalid_identifier' using errcode = '22023';
  end if;

  if p_identifier ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into v_profile
    from public.profiles p
    where p.id = p_identifier::uuid;
  else
    select * into v_profile
    from public.profiles p
    where lower(trim(p.username)) = lower(trim(p_identifier));
  end if;

  if v_profile.id is null then
    return jsonb_build_object(
      'meta', jsonb_build_object(
        'contract_version', 'v1',
        'found', false,
        'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      ),
      'data', jsonb_build_object('profile', null)
    );
  end if;

  v_profile_id := v_profile.id;
  v_is_own := v_viewer is not null and v_viewer = v_profile_id;

  if v_viewer is not null and not v_is_own then
    select exists (
      select 1 from public.followers f
      where f.follower_id = v_viewer and f.following_id = v_profile_id
    ) into v_is_following;

    select exists (
      select 1 from public.follow_requests fr
      where fr.requester_id = v_viewer and fr.target_id = v_profile_id
        and fr.status = 'pending'
    ) into v_is_requested;

    select exists (
      select 1 from public.followers f
      where f.follower_id = v_profile_id and f.following_id = v_viewer
    ) into v_follows_you;
  end if;

  v_can_view := v_is_own
    or coalesce(v_profile.is_private, false) = false
    or v_is_following;

  select count(*)::integer into v_followers_count
  from public.followers f where f.following_id = v_profile_id;

  select count(*)::integer into v_following_count
  from public.followers f where f.follower_id = v_profile_id;

  select jsonb_build_object(
    'id', r.id,
    'name', r.name,
    'slug', r.slug,
    'show_on_profile', coalesce(r.show_on_profile, true)
  )
  into v_owned_room
  from public.rooms r
  where r.owner_user_id = v_profile_id
  order by r.id
  limit 1;

  v_section_counts := jsonb_build_object(
    'has_room', v_owned_room is not null,
    'has_active_story', exists (
      select 1 from public.stories s
      where s.user_id = v_profile_id
        and s.created_at > (timezone('utc', now()) - interval '24 hours')
    ),
    'public_trades', case when v_can_view then (
      select count(*)::integer from public.trades t
      where t.user_id = v_profile_id and t.is_public is true
    ) else null end,
    'profile_posts', case when v_can_view then (
      select count(*)::integer from public.profile_posts pp
      where pp.user_id = v_profile_id
    ) else null end,
    'reels', case when v_can_view then (
      select count(*)::integer from public.reels r where r.user_id = v_profile_id
    ) else null end,
    'achievements', case when v_can_view then (
      select count(*)::integer from public.achievements a
      where a.user_id = v_profile_id and a.is_public = true
    ) else null end
  );

  if v_can_view then
    with eligible as (
      select t.pnl, t.rr
      from public.trades t
      where t.user_id = v_profile_id
        and t.is_public is true
        and coalesce(t.mode, '') <> 'backtest'
        and coalesce(t.account_type, '') <> 'backtest'
    ),
    payout as (
      select coalesce(sum(coalesce(a.value_numeric, 0)), 0)::numeric as payout_total
      from public.achievements a
      where a.user_id = v_profile_id
        and a.is_public is true
        and lower(trim(coalesce(a.achievement_type, ''))) in (
          'prop_firm_payout',
          'live_trading_payout',
          'payout'
        )
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
      'payout_total', (select payout_total from payout)
    )
    into v_public_stats
    from eligible, payout;
  end if;

  if v_can_view and v_tab = 'trades' then
    if p_cursor is not null and trim(p_cursor) <> '' then
      v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
      v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
    end if;

    with page as (
      select t.*
      from public.trades t
      where t.user_id = v_profile_id
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
    ),
    ids as (
      select array_agg(id) as trade_ids from trimmed
    )
    select
      coalesce(
        (select jsonb_agg(to_jsonb(tr) order by tr.created_at desc, tr.id desc) from trimmed tr),
        '[]'::jsonb
      ),
      (select count(*) > v_limit from page)
    into v_trades, v_has_more
    from ids;

    if v_has_more then
      select (to_char(tr.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || tr.id::text)
      into v_next_cursor
      from (
        select t.created_at, t.id
        from public.trades t
        where t.user_id = v_profile_id
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
      from jsonb_array_elements(v_trades) elem
      where elem ? 'id'
    ),
    like_counts as (
      select tl.trade_id, count(*)::integer as like_count,
        bool_or(v_viewer is not null and tl.user_id = v_viewer) as liked_by_me
      from public.trade_likes tl
      inner join trade_ids ti on ti.id = tl.trade_id
      group by tl.trade_id
    ),
    comment_counts as (
      select tc.trade_id, count(*)::integer as comment_count
      from public.trade_comments tc
      inner join trade_ids ti on ti.id = tc.trade_id
      group by tc.trade_id
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
    left join like_counts lc on lc.trade_id = ti.id
    left join comment_counts cc on cc.trade_id = ti.id;
  end if;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'found', true,
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_viewer
    ),
    'data', jsonb_build_object(
      'profile', jsonb_build_object(
        'id', v_profile.id,
        'username', v_profile.username,
        'name', v_profile.name,
        'bio', v_profile.bio,
        'avatar_url', v_profile.avatar_url,
        'trading_style', v_profile.trading_style,
        'trader_type', v_profile.trader_type,
        'primary_market', v_profile.primary_market,
        'started_trading', v_profile.started_trading,
        'is_private', v_profile.is_private,
        'created_at', v_profile.created_at
      ),
      'viewer', jsonb_build_object(
        'is_own_profile', v_is_own,
        'can_view_trades', v_can_view,
        'is_following', v_is_following,
        'is_requested', v_is_requested,
        'follows_you', v_follows_you
      ),
      'followers_count', v_followers_count,
      'following_count', v_following_count,
      'section_counts', v_section_counts,
      'public_stats', v_public_stats,
      'owned_room', v_owned_room,
      'active_tab', v_tab,
      'trades_page', case when v_tab = 'trades' and v_can_view then jsonb_build_object(
        'items', v_trades,
        'page_meta', jsonb_build_object(
          'limit', v_limit,
          'returned', coalesce(jsonb_array_length(v_trades), 0),
          'has_more', v_has_more,
          'next_cursor', v_next_cursor
        )
      ) else null end,
      'trade_engagement', case when v_tab = 'trades' and v_can_view then v_engagement else null end
    )
  );
end;
$$;

comment on function public.rpc_v1_profile_bootstrap(text, text, integer, text) is
  'Bounded Profile header + active-tab first page (read-only). contract_version v1 string.';

revoke all on function public.rpc_v1_profile_bootstrap(text, text, integer, text) from public;
grant execute on function public.rpc_v1_profile_bootstrap(text, text, integer, text) to authenticated;
grant execute on function public.rpc_v1_profile_bootstrap(text, text, integer, text) to anon;
