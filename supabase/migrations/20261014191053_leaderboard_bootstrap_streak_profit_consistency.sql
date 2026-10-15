-- Compute leaderboard win streak, profit percent, and consistency.
-- Formulas match native LeaderboardUserStatsAggregator. Sort those categories
-- across the full eligible set before pagination. Signature and other metrics
-- stay the same.

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
      t.id,
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
  ordered_trades as (
    select
      wt.user_id,
      coalesce(wt.pnl, 0)::numeric as pnl,
      (coalesce(wt.pnl, 0) > 0) as is_win,
      row_number() over (
        partition by wt.user_id
        order by wt.created_at asc nulls last, wt.id asc
      ) as seq
    from window_trades wt
  ),
  streak_groups as (
    select
      user_id,
      is_win,
      seq - row_number() over (
        partition by user_id, is_win
        order by seq
      ) as grp
    from ordered_trades
  ),
  best_streaks as (
    select user_id, max(streak)::integer as win_streak
    from (
      select user_id, count(*)::integer as streak
      from streak_groups
      where is_win
      group by user_id, grp
    ) runs
    group by user_id
  ),
  daily_pnl as (
    select
      wt.user_id,
      (wt.created_at at time zone 'America/New_York')::date as ny_day,
      sum(coalesce(wt.pnl, 0))::numeric as day_pnl
    from window_trades wt
    where wt.created_at is not null
    group by wt.user_id, (wt.created_at at time zone 'America/New_York')::date
  ),
  day_stats as (
    select
      user_id,
      count(*)::integer as trading_days,
      count(*) filter (where day_pnl > 0)::integer as profitable_days
    from daily_pnl
    group by user_id
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
      coalesce(sum(wt.pnl) filter (where coalesce(wt.pnl, 0) < 0), 0)::numeric as gross_losses,
      max(wt.pnl) filter (where coalesce(wt.pnl, 0) > 0) as biggest_win,
      coalesce(bs.win_streak, 0)::integer as win_streak,
      case
        when coalesce(ds.trading_days, 0) > 0 then
          ds.profitable_days::numeric / ds.trading_days::numeric * 100
        else null
      end as profit_percent
    from window_trades wt
    left join best_streaks bs on bs.user_id = wt.user_id
    left join day_stats ds on ds.user_id = wt.user_id
    group by wt.user_id, bs.win_streak, ds.trading_days, ds.profitable_days
    having count(*) > 0
  ),
  scored as (
    select
      ua.*,
      case
        when ua.gross_wins > 0 then
          least(
            100,
            greatest(
              0,
              (1 - coalesce(ua.biggest_win, 0) / ua.gross_wins) * 100
            )
          )
        else null
      end as consistency
    from user_agg ua
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
      ua.win_streak,
      ua.profit_percent,
      ua.consistency,
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
        -- iOS raw values are lowercased by this function before the case.
        when 'winstreak' then ua.win_streak::numeric
        when 'profitpercent' then coalesce(ua.profit_percent, -999999)
        when 'consistency' then coalesce(ua.consistency, -999999)
        else ua.total_pnl
      end as sort_key
    from scored ua
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
      or r.sort_key < v_cursor_sort
      or (
        r.sort_key = v_cursor_sort
        and v_cursor_id is not null
        and r.profile_id > v_cursor_id
      )
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
            'win_streak', t.win_streak,
            'profit_percent', t.profit_percent,
            'consistency', t.consistency,
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
  'Windowed leaderboard rankings. Win streak, profit percent, and consistency are computed per trader; those categories sort the full window before pagination.';

revoke all on function public.rpc_v1_leaderboard_bootstrap(text, text, text, integer, text) from public;
grant execute on function public.rpc_v1_leaderboard_bootstrap(text, text, text, integer, text) to authenticated;
grant execute on function public.rpc_v1_leaderboard_bootstrap(text, text, text, integer, text) to anon;
