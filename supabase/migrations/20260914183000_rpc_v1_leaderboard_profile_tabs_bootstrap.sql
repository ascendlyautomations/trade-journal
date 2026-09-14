-- Server-windowed leaderboard + paginated profile tab RPCs (Backend V2 native scaling).

-- ---------------------------------------------------------------------------
-- Leaderboard bootstrap — ranked page only (no full trade corpus download).
-- ---------------------------------------------------------------------------

create or replace function public.rpc_v1_leaderboard_bootstrap(
  p_timeframe text default 'month',
  p_category text default 'pnl',
  p_audience text default 'all',
  p_limit integer default 100,
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
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 100);
  v_timeframe text := lower(trim(coalesce(p_timeframe, 'month')));
  v_category text := lower(trim(coalesce(p_category, 'pnl')));
  v_audience text := lower(trim(coalesce(p_audience, 'all')));
  v_cursor_sort numeric;
  v_cursor_id uuid;
  v_now timestamptz := timezone('utc', now());
  v_cutoff timestamptz;
  v_ytd_start date;
  v_rows jsonb := '[]'::jsonb;
  v_next_cursor text := null;
begin
  if p_cursor is not null and trim(p_cursor) <> '' then
    v_cursor_sort := nullif(split_part(p_cursor, '|', 1), '')::numeric;
    v_cursor_id := nullif(split_part(p_cursor, '|', 2), '')::uuid;
  end if;

  case v_timeframe
    when 'today' then
      v_cutoff := date_trunc('day', timezone('America/New_York', v_now));
    when 'week' then
      v_cutoff := v_now - interval '7 days';
    when 'month' then
      v_cutoff := v_now - interval '30 days';
    when 'year' then
      v_ytd_start := make_date(extract(year from timezone('America/New_York', v_now))::int, 1, 1);
      v_cutoff := v_ytd_start::timestamptz;
    else
      v_cutoff := null;
  end case;

  with window_trades as (
    select
      t.user_id,
      t.pnl,
      t.rr,
      t.created_at
    from public.trades t
    inner join public.profiles p on p.id = t.user_id
    where coalesce(p.is_private, false) = false
      and coalesce(t.is_public, false) = true
      and coalesce(lower(trim(t.mode)), '') is distinct from 'backtest'
      and coalesce(lower(trim(t.account_type)), '') is distinct from 'backtest'
      and (
        v_cutoff is null
        or t.created_at >= v_cutoff
      )
      and (
        v_timeframe <> 'today'
        or t.created_at < date_trunc('day', timezone('America/New_York', v_now)) + interval '1 day'
      )
  ),
  user_agg as (
    select
      wt.user_id,
      coalesce(sum(wt.pnl), 0)::numeric as total_pnl,
      count(*)::integer as trade_count,
      avg(wt.rr) filter (where wt.rr is not null) as avg_rr,
      count(*) filter (where coalesce(wt.pnl, 0) > 0)::integer as win_count,
      count(*) filter (where coalesce(wt.pnl, 0) < 0)::integer as loss_count,
      coalesce(sum(wt.pnl) filter (where coalesce(wt.pnl, 0) > 0), 0)::numeric as gross_wins,
      coalesce(sum(wt.pnl) filter (where coalesce(wt.pnl, 0) < 0), 0)::numeric as gross_losses
    from window_trades wt
    group by wt.user_id
    having count(*) > 0
  ),
  ranked as (
    select
      ua.user_id as profile_id,
      pr.username,
      pr.name as display_name,
      pr.avatar_url,
      fc.cnt as follower_count,
      ua.total_pnl,
      ua.trade_count,
      ua.avg_rr,
      case when ua.trade_count > 0
        then round(ua.win_count::numeric / ua.trade_count::numeric, 6)
        else null end as win_rate,
      case when ua.gross_losses < 0
        then round(ua.gross_wins / abs(ua.gross_losses), 6)
        else null end as profit_factor,
      case when ua.trade_count > 0 then
        round(
          (ua.win_count::numeric / ua.trade_count::numeric)
            * coalesce(ua.gross_wins / nullif(ua.win_count, 0), 0)
          - (ua.loss_count::numeric / ua.trade_count::numeric)
            * coalesce(abs(ua.gross_losses) / nullif(ua.loss_count, 0), 0),
          6
        )
        else null end as expectancy,
      case v_category
        when 'win_rate' then case when ua.trade_count > 0 then ua.win_count::numeric / ua.trade_count else -999999 end
        when 'profit_factor' then coalesce(
          case when ua.gross_losses < 0 then ua.gross_wins / abs(ua.gross_losses) else -999999 end,
          -999999
        )
        when 'expectancy' then coalesce(
          case when ua.trade_count > 0 then
            (ua.win_count::numeric / ua.trade_count)
              * coalesce(ua.gross_wins / nullif(ua.win_count, 0), 0)
            - (ua.loss_count::numeric / ua.trade_count)
              * coalesce(abs(ua.gross_losses) / nullif(ua.loss_count, 0), 0)
          else -999999 end,
          -999999
        )
        when 'rr' then coalesce(ua.avg_rr, -999999)
        when 'followers' then coalesce(fc.cnt, 0)::numeric
        else ua.total_pnl
      end as sort_key
    from user_agg ua
    inner join public.profiles pr on pr.id = ua.user_id
    left join lateral (
      select count(*)::integer as cnt
      from public.followers f
      where f.following_id = ua.user_id
    ) fc on true
    where (
      v_audience = 'all'
      or (
        v_viewer is not null
        and v_audience = 'following'
        and exists (
          select 1 from public.followers f
          where f.follower_id = v_viewer and f.following_id = ua.user_id
        )
      )
      or (
        v_viewer is not null
        and v_audience = 'friends'
        and exists (
          select 1 from public.followers f1
          where f1.follower_id = v_viewer and f1.following_id = ua.user_id
        )
        and exists (
          select 1 from public.followers f2
          where f2.follower_id = ua.user_id and f2.following_id = v_viewer
        )
      )
    )
  ),
  page as (
    select *
    from ranked r
    where (
      v_cursor_sort is null
      or (r.sort_key, r.profile_id) < (v_cursor_sort, v_cursor_id)
    )
    order by r.sort_key desc, r.profile_id asc
    limit v_limit + 1
  ),
  trimmed as (
    select * from page limit v_limit
  ),
  page_count as (
    select count(*)::integer as cnt from page
  )
  select
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'profile_id', t.profile_id,
            'username', t.username,
            'display_name', t.display_name,
            'avatar_url', t.avatar_url,
            'follower_count', t.follower_count,
            'total_pnl', t.total_pnl,
            'trade_count', t.trade_count,
            'avg_rr', t.avg_rr,
            'win_rate', t.win_rate,
            'profit_factor', t.profit_factor,
            'expectancy', t.expectancy,
            'win_streak', 0,
            'profit_percent', null,
            'consistency', null,
            'sort_key', t.sort_key
          )
          order by t.sort_key desc, t.profile_id asc
        )
        from trimmed t
      ),
      '[]'::jsonb
    ),
    (
      select case when pc.cnt > v_limit then
        (last_row.sort_key::text || '|' || last_row.profile_id::text)
      else null end
      from page_count pc,
      lateral (
        select sort_key, profile_id
        from trimmed
        order by sort_key asc, profile_id desc
        limit 1
      ) last_row
    )
  into v_rows, v_next_cursor;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_viewer
    ),
    'data', jsonb_build_object(
      'timeframe', v_timeframe,
      'category', v_category,
      'rows', coalesce(v_rows, '[]'::jsonb),
      'next_cursor', v_next_cursor
    )
  );
end;
$$;

comment on function public.rpc_v1_leaderboard_bootstrap(text, text, text, integer, text) is
  'Windowed leaderboard rankings — paginated rows for timeframe/audience/category (no full trade corpus).';

revoke all on function public.rpc_v1_leaderboard_bootstrap(text, text, text, integer, text) from public;
grant execute on function public.rpc_v1_leaderboard_bootstrap(text, text, text, integer, text) to authenticated;
grant execute on function public.rpc_v1_leaderboard_bootstrap(text, text, text, integer, text) to anon;

-- ---------------------------------------------------------------------------
-- Profile tab RPCs — cursor/keyset pages (24 default).
-- ---------------------------------------------------------------------------

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
      'meta', jsonb_build_object('contract_version', 'v1', 'found', false),
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
    coalesce(jsonb_agg(to_jsonb(tr) order by tr.created_at desc, tr.id desc), '[]'::jsonb),
    (select count(*) > v_limit from page)
  into v_items, v_has_more
  from trimmed tr;

  if v_has_more then
    select (to_char(tr.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || tr.id::text)
    into v_next_cursor
    from (
      select created_at, id from trimmed
      order by created_at asc, id asc
      limit 1
    ) tr;
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

create or replace function public.rpc_v1_profile_tab_posts(
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
  v_next_cursor text := null;
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
  from public.profiles p where p.id = p_profile_id;

  if not coalesce(v_can_view, false) then
    return jsonb_build_object(
      'meta', jsonb_build_object('contract_version', 'v1', 'found', false),
      'data', jsonb_build_object('tab', 'posts', 'items', '[]'::jsonb, 'engagement', '{}'::jsonb, 'next_cursor', null)
    );
  end if;

  if p_cursor is not null and trim(p_cursor) <> '' then
    v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
    v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
  end if;

  with page as (
    select pp.*
    from public.profile_posts pp
    where pp.user_id = p_profile_id
      and (
        v_cursor_ts is null
        or (pp.created_at, pp.id) < (v_cursor_ts, v_cursor_id)
      )
    order by coalesce(pp.is_pinned, false) desc, pp.created_at desc, pp.id desc
    limit v_limit + 1
  ),
  trimmed as (
    select * from page limit v_limit
  )
  select
    coalesce(
      jsonb_agg(
        to_jsonb(tr)
        order by coalesce(tr.is_pinned, false) desc, tr.created_at desc, tr.id desc
      ),
      '[]'::jsonb
    ),
    (
      select case when (select count(*) from page) > v_limit then
        (to_char(last_row.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || last_row.id::text)
      else null end
      from (
        select created_at, id from trimmed
        order by coalesce(is_pinned, false) asc, created_at asc, id asc
        limit 1
      ) last_row
    )
  into v_items, v_next_cursor
  from trimmed tr;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'found', true,
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_viewer
    ),
    'data', jsonb_build_object(
      'tab', 'posts',
      'items', v_items,
      'engagement', '{}'::jsonb,
      'next_cursor', v_next_cursor
    )
  );
end;
$$;

create or replace function public.rpc_v1_profile_tab_reels(
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
  v_next_cursor text := null;
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
  from public.profiles p where p.id = p_profile_id;

  if not coalesce(v_can_view, false) then
    return jsonb_build_object(
      'meta', jsonb_build_object('contract_version', 'v1', 'found', false),
      'data', jsonb_build_object('tab', 'reels', 'items', '[]'::jsonb, 'engagement', '{}'::jsonb, 'next_cursor', null)
    );
  end if;

  if p_cursor is not null and trim(p_cursor) <> '' then
    v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
    v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
  end if;

  with page as (
    select r.*
    from public.reels r
    where r.user_id = p_profile_id
      and (
        v_cursor_ts is null
        or (r.created_at, r.id) < (v_cursor_ts, v_cursor_id)
      )
    order by r.created_at desc, r.id desc
    limit v_limit + 1
  ),
  trimmed as (
    select * from page limit v_limit
  )
  select
    coalesce(jsonb_agg(to_jsonb(tr) order by tr.created_at desc, tr.id desc), '[]'::jsonb),
    (
      select case when (select count(*) from page) > v_limit then
        (to_char(last_row.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || last_row.id::text)
      else null end
      from (
        select created_at, id from trimmed
        order by created_at asc, id asc
        limit 1
      ) last_row
    )
  into v_items, v_next_cursor
  from trimmed tr;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'found', true,
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_viewer
    ),
    'data', jsonb_build_object(
      'tab', 'reels',
      'items', v_items,
      'engagement', '{}'::jsonb,
      'next_cursor', v_next_cursor
    )
  );
end;
$$;

create or replace function public.rpc_v1_profile_tab_achievements(
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
  v_is_owner boolean := false;
  v_items jsonb := '[]'::jsonb;
  v_next_cursor text := null;
begin
  if p_profile_id is null then
    raise exception 'invalid_profile_id' using errcode = '22023';
  end if;

  v_is_owner := v_viewer is not null and v_viewer = p_profile_id;

  select (
    v_is_owner
    or coalesce(p.is_private, false) = false
    or exists (
      select 1 from public.followers f
      where f.follower_id = v_viewer and f.following_id = p_profile_id
    )
  ) into v_can_view
  from public.profiles p where p.id = p_profile_id;

  if not coalesce(v_can_view, false) then
    return jsonb_build_object(
      'meta', jsonb_build_object('contract_version', 'v1', 'found', false),
      'data', jsonb_build_object('tab', 'achievements', 'items', '[]'::jsonb, 'engagement', '{}'::jsonb, 'next_cursor', null)
    );
  end if;

  if p_cursor is not null and trim(p_cursor) <> '' then
    v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
    v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
  end if;

  with page as (
    select a.*
    from public.achievements a
    where a.user_id = p_profile_id
      and (v_is_owner or coalesce(a.is_public, false) = true)
      and (
        v_cursor_ts is null
        or (a.created_at, a.id) < (v_cursor_ts, v_cursor_id)
      )
    order by a.sort_order asc nulls last, a.created_at desc, a.id desc
    limit v_limit + 1
  ),
  trimmed as (
    select * from page limit v_limit
  )
  select
    coalesce(
      jsonb_agg(to_jsonb(tr) order by tr.sort_order asc nulls last, tr.created_at desc, tr.id desc),
      '[]'::jsonb
    ),
    (
      select case when (select count(*) from page) > v_limit then
        (to_char(last_row.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || last_row.id::text)
      else null end
      from (
        select created_at, id from trimmed
        order by sort_order desc nulls first, created_at asc, id asc
        limit 1
      ) last_row
    )
  into v_items, v_next_cursor
  from trimmed tr;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'found', true,
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_viewer
    ),
    'data', jsonb_build_object(
      'tab', 'achievements',
      'items', v_items,
      'engagement', '{}'::jsonb,
      'next_cursor', v_next_cursor
    )
  );
end;
$$;

revoke all on function public.rpc_v1_profile_tab_trades(uuid, integer, text) from public;
grant execute on function public.rpc_v1_profile_tab_trades(uuid, integer, text) to authenticated;
grant execute on function public.rpc_v1_profile_tab_trades(uuid, integer, text) to anon;

revoke all on function public.rpc_v1_profile_tab_posts(uuid, integer, text) from public;
grant execute on function public.rpc_v1_profile_tab_posts(uuid, integer, text) to authenticated;
grant execute on function public.rpc_v1_profile_tab_posts(uuid, integer, text) to anon;

revoke all on function public.rpc_v1_profile_tab_reels(uuid, integer, text) from public;
grant execute on function public.rpc_v1_profile_tab_reels(uuid, integer, text) to authenticated;
grant execute on function public.rpc_v1_profile_tab_reels(uuid, integer, text) to anon;

revoke all on function public.rpc_v1_profile_tab_achievements(uuid, integer, text) from public;
grant execute on function public.rpc_v1_profile_tab_achievements(uuid, integer, text) to authenticated;
grant execute on function public.rpc_v1_profile_tab_achievements(uuid, integer, text) to anon;
