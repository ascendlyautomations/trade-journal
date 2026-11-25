-- Leaderboard curve: all metrics + payouts category (supersedes curve limits in 20261124160000).
-- Adds public payout rankings, follower / streak / consistency historical curves, server forward-fill.

create or replace function public.leaderboard_v1_normalize_category(p_category text)
returns text
language sql
immutable
parallel safe
set search_path = public, pg_temp
as $$
  with raw as (
    select lower(trim(coalesce(p_category, 'pnl'))) as cat
  )
  select case replace((select cat from raw), '_', '')
    when 'winrate' then 'win_rate'
    when 'profitfactor' then 'profit_factor'
    when 'profitpercent' then 'profit_percent'
    when 'winstreak' then 'win_streak'
    when 'followers' then 'followers'
    when 'consistency' then 'consistency'
    when 'expectancy' then 'expectancy'
    when 'rr' then 'rr'
    when 'payouts' then 'payouts'
    when 'pnl' then 'pnl'
    else (select cat from raw)
  end;
$$;

create or replace function public.leaderboard_v1_is_payout_achievement(p_type text)
returns boolean
language sql
immutable
parallel safe
set search_path = public, pg_temp
as $$
  select lower(trim(coalesce(p_type, ''))) in (
    'prop_firm_payout',
    'live_trading_payout',
    'payout'
  );
$$;

comment on function public.leaderboard_v1_is_payout_achievement(text) is
  'Eligible public profile payout achievement types (prop, live, legacy).';

grant execute on function public.leaderboard_v1_is_payout_achievement(text) to authenticated;
grant execute on function public.leaderboard_v1_is_payout_achievement(text) to anon;

comment on function public.leaderboard_v1_normalize_category(text) is
  'Maps iOS LeaderboardCategory rawValue slugs to canonical leaderboard metric keys.';

grant execute on function public.leaderboard_v1_normalize_category(text) to authenticated;
grant execute on function public.leaderboard_v1_normalize_category(text) to anon;

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
  v_category_wire text := public.leaderboard_v1_normalize_category(p_category);
  v_audience text := lower(trim(coalesce(p_audience, 'all')));
  v_cursor_sort numeric;
  v_cursor_id uuid;
  v_now timestamptz := timezone('utc', now());
  v_ny_now timestamp;
  v_cutoff timestamptz;
  v_today_end timestamptz;
  v_ytd_start date;
  v_rows jsonb := '[]'::jsonb;
  v_next_cursor text := null;
begin
  v_ny_now := v_now at time zone 'America/New_York';

  if p_cursor is not null and trim(p_cursor) <> '' then
    v_cursor_sort := nullif(split_part(p_cursor, '|', 1), '')::numeric;
    v_cursor_id := nullif(split_part(p_cursor, '|', 2), '')::uuid;
  end if;

  case v_timeframe
    when 'today' then
      v_cutoff := (date_trunc('day', v_ny_now) at time zone 'America/New_York');
      v_today_end := ((date_trunc('day', v_ny_now) + interval '1 day') at time zone 'America/New_York');
    when 'week' then
      v_cutoff := v_now - interval '7 days';
      v_today_end := null;
    when 'month' then
      v_cutoff := v_now - interval '30 days';
      v_today_end := null;
    when 'year' then
      v_ytd_start := make_date(extract(year from v_ny_now)::int, 1, 1);
      v_cutoff := (v_ytd_start::timestamp at time zone 'America/New_York');
      v_today_end := null;
    else
      v_cutoff := null;
      v_today_end := null;
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
      and (v_cutoff is null or t.created_at >= v_cutoff)
      and (
        v_timeframe <> 'today'
        or (v_today_end is not null and t.created_at < v_today_end)
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
  payout_agg as (
    select
      a.user_id,
      coalesce(sum(a.value_numeric), 0)::numeric as payout_total
    from public.achievements a
    inner join public.profiles pr on pr.id = a.user_id
    where coalesce(pr.is_private, false) = false
      and coalesce(a.is_public, false) = true
      and public.leaderboard_v1_is_payout_achievement(a.achievement_type)
      and (v_cutoff is null or a.achieved_at >= v_cutoff)
      and (
        v_timeframe <> 'today'
        or (v_today_end is not null and a.achieved_at < v_today_end)
      )
    group by a.user_id
    having coalesce(sum(a.value_numeric), 0) > 0
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
      case v_category_wire
        when 'win_rate' then
          case when ua.trade_count > 0 then ua.win_count::numeric / ua.trade_count else -999999 end
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
        when 'win_streak' then ua.win_streak::numeric
        when 'profit_percent' then coalesce(ua.profit_percent, -999999)
        when 'consistency' then coalesce(ua.consistency, -999999)
        when 'payouts' then coalesce(pa.payout_total, -999999)
        else ua.total_pnl
      end as sort_key,
      coalesce(pa.payout_total, 0)::numeric as payout_total
    from scored ua
    inner join public.profiles pr on pr.id = ua.user_id
    left join payout_agg pa on pa.user_id = ua.user_id
    left join lateral (
      select count(*)::integer as cnt
      from public.followers f
      where f.following_id = ua.user_id
    ) fc on true
    where v_category_wire <> 'payouts'
      and (
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

    union all

    select
      pa.user_id as profile_id,
      pr.username,
      pr.name as display_name,
      pr.avatar_url,
      fc.cnt as follower_count,
      coalesce(ua.total_pnl, 0) as total_pnl,
      coalesce(ua.trade_count, 0) as trade_count,
      ua.avg_rr,
      coalesce(ua.win_streak, 0) as win_streak,
      ua.profit_percent,
      ua.consistency,
      case when coalesce(ua.trade_count, 0) > 0
        then round(ua.win_count::numeric / ua.trade_count::numeric, 6)
        else null end as win_rate,
      case when coalesce(ua.gross_losses, 0) < 0
        then round(ua.gross_wins / abs(ua.gross_losses), 6)
        else null end as profit_factor,
      case when coalesce(ua.trade_count, 0) > 0 then
        round(
          (ua.win_count::numeric / ua.trade_count::numeric)
            * coalesce(ua.gross_wins / nullif(ua.win_count, 0), 0)
          - (ua.loss_count::numeric / ua.trade_count::numeric)
            * coalesce(abs(ua.gross_losses) / nullif(ua.loss_count, 0), 0),
          6
        )
        else null end as expectancy,
      pa.payout_total as sort_key,
      pa.payout_total
    from payout_agg pa
    inner join public.profiles pr on pr.id = pa.user_id
    left join scored ua on ua.user_id = pa.user_id
    left join lateral (
      select count(*)::integer as cnt
      from public.followers f
      where f.following_id = pa.user_id
    ) fc on true
    where v_category_wire = 'payouts'
      and (
        v_audience = 'all'
        or (
          v_viewer is not null
          and v_audience = 'following'
          and exists (
            select 1 from public.followers f
            where f.follower_id = v_viewer and f.following_id = pa.user_id
          )
        )
        or (
          v_viewer is not null
          and v_audience = 'friends'
          and exists (
            select 1 from public.followers f1
            where f1.follower_id = v_viewer and f1.following_id = pa.user_id
          )
          and exists (
            select 1 from public.followers f2
            where f2.follower_id = pa.user_id and f2.following_id = v_viewer
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
            'payout_total', t.payout_total,
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
      'category', v_category_wire,
      'rows', coalesce(v_rows, '[]'::jsonb),
      'next_cursor', v_next_cursor
    )
  );
end;
$$;

create or replace function public.rpc_v1_leaderboard_curve(
  p_timeframe text default 'month',
  p_category text default 'pnl',
  p_audience text default 'all'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_viewer uuid := auth.uid();
  v_timeframe text := lower(trim(coalesce(p_timeframe, 'month')));
  v_audience text := lower(trim(coalesce(p_audience, 'all')));
  v_category_wire text := public.leaderboard_v1_normalize_category(p_category);
  v_now timestamptz := timezone('utc', now());
  v_ny_now timestamp;
  v_cutoff timestamptz;
  v_today_end timestamptz;
  v_ytd_start date;
  v_highest uuid;
  v_lowest uuid;
  v_metric_format text := 'currency';
  v_points jsonb := '[]'::jsonb;
  v_supported boolean := true;
  v_chart_max_days constant integer := 180;
begin
  v_ny_now := v_now at time zone 'America/New_York';

  case v_category_wire
    when 'pnl', 'expectancy', 'payouts' then v_metric_format := 'currency';
    when 'win_rate', 'profit_percent', 'consistency' then v_metric_format := 'percent';
    when 'profit_factor', 'rr', 'win_streak', 'followers' then v_metric_format := 'ratio';
    else v_metric_format := 'currency';
  end case;

  case v_timeframe
    when 'today' then
      v_cutoff := (date_trunc('day', v_ny_now) at time zone 'America/New_York');
      v_today_end := ((date_trunc('day', v_ny_now) + interval '1 day') at time zone 'America/New_York');
    when 'week' then
      v_cutoff := v_now - interval '7 days';
      v_today_end := null;
    when 'month' then
      v_cutoff := v_now - interval '30 days';
      v_today_end := null;
    when 'year' then
      v_ytd_start := make_date(extract(year from v_ny_now)::int, 1, 1);
      v_cutoff := (v_ytd_start::timestamp at time zone 'America/New_York');
      v_today_end := null;
    else
      v_cutoff := null;
      v_today_end := null;
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
      and (v_cutoff is null or t.created_at >= v_cutoff)
      and (
        v_timeframe <> 'today'
        or (v_today_end is not null and t.created_at < v_today_end)
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
      seq,
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
  daily_cum as (
    select
      user_id,
      ny_day,
      day_pnl,
      sum(day_pnl) over (partition by user_id order by ny_day) as cum_day_pnl,
      count(*) over (partition by user_id order by ny_day) as trading_days,
      sum(case when day_pnl > 0 then 1 else 0 end)
        over (partition by user_id order by ny_day) as profitable_days
    from daily_pnl
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
  payout_agg as (
    select
      a.user_id,
      coalesce(sum(a.value_numeric), 0)::numeric as payout_total
    from public.achievements a
    inner join public.profiles pr on pr.id = a.user_id
    where coalesce(pr.is_private, false) = false
      and coalesce(a.is_public, false) = true
      and public.leaderboard_v1_is_payout_achievement(a.achievement_type)
      and (v_cutoff is null or a.achieved_at >= v_cutoff)
      and (
        v_timeframe <> 'today'
        or (v_today_end is not null and a.achieved_at < v_today_end)
      )
    group by a.user_id
    having coalesce(sum(a.value_numeric), 0) > 0
  ),
  follower_ranked as (
    select
      p.id as profile_id,
      fc.cnt::numeric as sort_key
    from public.profiles p
    inner join lateral (
      select count(*)::integer as cnt
      from public.followers f
      where f.following_id = p.id
    ) fc on fc.cnt > 0
    where coalesce(p.is_private, false) = false
      and (
        v_audience = 'all'
        or (
          v_viewer is not null
          and v_audience = 'following'
          and exists (
            select 1 from public.followers f
            where f.follower_id = v_viewer and f.following_id = p.id
          )
        )
        or (
          v_viewer is not null
          and v_audience = 'friends'
          and exists (
            select 1 from public.followers f1
            where f1.follower_id = v_viewer and f1.following_id = p.id
          )
          and exists (
            select 1 from public.followers f2
            where f2.follower_id = p.id and f2.following_id = v_viewer
          )
        )
      )
  ),
  ranked as (
    select
      ua.user_id as profile_id,
      case v_category_wire
        when 'win_rate' then
          case when ua.trade_count > 0 then ua.win_count::numeric / ua.trade_count else -999999 end
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
        when 'win_streak' then ua.win_streak::numeric
        when 'profit_percent' then coalesce(ua.profit_percent, -999999)
        when 'consistency' then coalesce(ua.consistency, -999999)
        when 'payouts' then coalesce(pa.payout_total, -999999)
        else ua.total_pnl
      end as sort_key
    from scored ua
    inner join public.profiles pr on pr.id = ua.user_id
    left join payout_agg pa on pa.user_id = ua.user_id
    where v_category_wire not in ('followers', 'payouts')
      and (
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

    union all

    select profile_id, sort_key
    from follower_ranked
    where v_category_wire = 'followers'

    union all

    select pa.user_id as profile_id, pa.payout_total as sort_key
    from payout_agg pa
    inner join public.profiles pr on pr.id = pa.user_id
    where v_category_wire = 'payouts'
      and (
        v_audience = 'all'
        or (
          v_viewer is not null
          and v_audience = 'following'
          and exists (
            select 1 from public.followers f
            where f.follower_id = v_viewer and f.following_id = pa.user_id
          )
        )
        or (
          v_viewer is not null
          and v_audience = 'friends'
          and exists (
            select 1 from public.followers f1
            where f1.follower_id = v_viewer and f1.following_id = pa.user_id
          )
          and exists (
            select 1 from public.followers f2
            where f2.follower_id = pa.user_id and f2.following_id = v_viewer
          )
        )
      )
  ),
  eligible as (
    select profile_id from ranked
  ),
  anchors as (
    select
      (select profile_id from ranked order by sort_key desc, profile_id asc limit 1) as highest_id,
      (select profile_id from ranked order by sort_key asc, profile_id desc limit 1) as lowest_id
  ),
  scoped_trades as (
    select wt.*
    from window_trades wt
    inner join eligible e on e.profile_id = wt.user_id
  ),
  trade_running as (
    select
      st.user_id,
      st.id,
      st.created_at,
      (st.created_at at time zone 'America/New_York')::date as ny_day,
      coalesce(st.pnl, 0)::numeric as pnl,
      st.rr,
      sum(coalesce(st.pnl, 0)) over w as cum_pnl,
      count(*) over w as cum_trades,
      sum(case when coalesce(st.pnl, 0) > 0 then 1 else 0 end) over w as cum_wins,
      sum(case when coalesce(st.pnl, 0) < 0 then 1 else 0 end) over w as cum_losses,
      coalesce(
        sum(coalesce(st.pnl, 0)) filter (where coalesce(st.pnl, 0) > 0) over w,
        0
      )::numeric as cum_gross_wins,
      coalesce(
        sum(coalesce(st.pnl, 0)) filter (where coalesce(st.pnl, 0) < 0) over w,
        0
      )::numeric as cum_gross_losses,
      avg(st.rr) filter (where st.rr is not null) over w as cum_avg_rr,
      max(coalesce(st.pnl, 0)) filter (where coalesce(st.pnl, 0) > 0) over w as cum_biggest_win
    from scoped_trades st
    window w as (partition by st.user_id order by st.created_at asc nulls last, st.id asc)
  ),
  ordered_scoped as (
    select
      st.user_id,
      st.id,
      st.created_at,
      (st.created_at at time zone 'America/New_York')::date as ny_day,
      coalesce(st.pnl, 0)::numeric as pnl,
      (coalesce(st.pnl, 0) > 0) as is_win,
      row_number() over (
        partition by st.user_id
        order by st.created_at asc nulls last, st.id asc
      ) as seq
    from scoped_trades st
  ),
  scoped_streak_groups as (
    select
      user_id,
      is_win,
      seq,
      seq - row_number() over (
        partition by user_id, is_win
        order by seq
      ) as grp
    from ordered_scoped
  ),
  scoped_streak_lens as (
    select user_id, grp, count(*)::integer as run_len
    from scoped_streak_groups
    where is_win
    group by user_id, grp
  ),
  trade_max_streak as (
    select
      os.user_id,
      os.id,
      os.created_at,
      os.ny_day,
      (
        select coalesce(max(ssl.run_len), 0)
        from scoped_streak_lens ssl
        inner join scoped_streak_groups sg
          on sg.user_id = ssl.user_id
         and sg.grp = ssl.grp
        where ssl.user_id = os.user_id
          and sg.is_win
          and sg.seq <= os.seq
      ) as max_streak_so_far
    from ordered_scoped os
  ),
  eod_trade as (
    select distinct on (user_id, ny_day)
      user_id,
      ny_day,
      cum_pnl,
      cum_trades,
      cum_wins,
      cum_losses,
      cum_gross_wins,
      cum_gross_losses,
      cum_avg_rr,
      cum_biggest_win
    from trade_running
    where created_at is not null
    order by user_id, ny_day, created_at desc, id desc
  ),
  eod_win_streak as (
    select distinct on (user_id, ny_day)
      user_id,
      ny_day,
      max_streak_so_far::numeric as metric_value
    from trade_max_streak
  ),
  follower_hist as (
    select
      f.following_id as user_id,
      f.created_at
    from public.followers f
    inner join eligible e on e.profile_id = f.following_id
    where f.created_at is not null
  ),
  follower_running as (
    select
      user_id,
      created_at,
      (created_at at time zone 'America/New_York')::date as ny_day,
      count(*) over (
        partition by user_id
        order by created_at asc nulls last
      )::numeric as metric_value
    from follower_hist
  ),
  follower_eod as (
    select distinct on (user_id, ny_day)
      user_id,
      ny_day,
      metric_value
    from follower_running
    order by user_id, ny_day, created_at desc
  ),
  payout_events as (
    select
      a.user_id,
      a.id,
      a.achieved_at,
      coalesce(a.value_numeric, 0)::numeric as amount
    from public.achievements a
    inner join eligible e on e.profile_id = a.user_id
    where coalesce(a.is_public, false) = true
      and public.leaderboard_v1_is_payout_achievement(a.achievement_type)
      and a.achieved_at is not null
      and (v_cutoff is null or a.achieved_at >= v_cutoff)
      and (
        v_timeframe <> 'today'
        or (v_today_end is not null and a.achieved_at < v_today_end)
      )
  ),
  payout_running as (
    select
      user_id,
      achieved_at,
      (achieved_at at time zone 'America/New_York')::date as ny_day,
      sum(amount) over (
        partition by user_id
        order by achieved_at asc nulls last, id asc
      )::numeric as metric_value
    from payout_events
  ),
  payout_eod as (
    select distinct on (user_id, ny_day)
      user_id,
      ny_day,
      metric_value
    from payout_running
    order by user_id, ny_day, achieved_at desc
  ),
  eod_metrics as (
    select
      et.user_id,
      et.ny_day,
      case v_category_wire
        when 'pnl' then et.cum_pnl
        when 'win_rate' then
          case when et.cum_trades > 0 then et.cum_wins::numeric / et.cum_trades else null end
        when 'rr' then et.cum_avg_rr
        when 'profit_factor' then
          case when et.cum_gross_losses < 0
            then et.cum_gross_wins / abs(et.cum_gross_losses)
            else null
          end
        when 'expectancy' then
          case when et.cum_trades > 0 then
            (et.cum_wins::numeric / et.cum_trades)
              * coalesce(et.cum_gross_wins / nullif(et.cum_wins, 0), 0)
            - (et.cum_losses::numeric / et.cum_trades)
              * coalesce(abs(et.cum_gross_losses) / nullif(et.cum_losses, 0), 0)
          else null end
        when 'consistency' then
          case when et.cum_gross_wins > 0 then
            least(
              100,
              greatest(
                0,
                (1 - coalesce(et.cum_biggest_win, 0) / et.cum_gross_wins) * 100
              )
            )
          else null end
        else et.cum_pnl
      end as metric_value
    from eod_trade et
    where v_category_wire in (
      'pnl', 'win_rate', 'rr', 'profit_factor', 'expectancy', 'consistency'
    )
    union all
    select
      dc.user_id,
      dc.ny_day,
      case when dc.trading_days > 0
        then dc.profitable_days::numeric / dc.trading_days::numeric * 100
        else null
      end as metric_value
    from daily_cum dc
    inner join eligible e on e.profile_id = dc.user_id
    where v_category_wire = 'profit_percent'
    union all
    select user_id, ny_day, metric_value
    from eod_win_streak
    where v_category_wire = 'win_streak'
    union all
    select user_id, ny_day, metric_value
    from follower_eod
    where v_category_wire = 'followers'
    union all
    select user_id, ny_day, metric_value
    from payout_eod
    where v_category_wire = 'payouts'
  ),
  user_day_spans as (
    select
      user_id,
      ny_day,
      metric_value,
      lead(ny_day, 1) over (
        partition by user_id
        order by ny_day
      ) as next_ny_day
    from eod_metrics
    where metric_value is not null
  ),
  day_bounds as (
    select
      count(*)::integer as day_count,
      max(ny_day) as max_day
    from (select distinct ny_day from eod_metrics where ny_day is not null) d
  ),
  day_series as (
    select d.ny_day
    from (select distinct ny_day from eod_metrics where ny_day is not null) d
    cross join day_bounds b
    where b.day_count <= v_chart_max_days
       or d.ny_day >= (b.max_day - (v_chart_max_days - 1))
  ),
  user_day_filled as (
    select
      ds.ny_day,
      s.user_id,
      s.metric_value
    from day_series ds
    inner join user_day_spans s
      on ds.ny_day >= s.ny_day
     and (s.next_ny_day is null or ds.ny_day < s.next_ny_day)
    inner join eligible e on e.profile_id = s.user_id
  ),
  bucketed as (
    select
      u.ny_day,
      max(u.metric_value) filter (where u.user_id = a.highest_id) as highest,
      max(u.metric_value) filter (where u.user_id = a.lowest_id) as lowest,
      max(u.metric_value) filter (where v_viewer is not null and u.user_id = v_viewer) as you,
      avg(u.metric_value) filter (where u.metric_value is not null) as average,
      count(u.metric_value) filter (where u.metric_value is not null)::integer as population_count
    from user_day_filled u
    cross join anchors a
    group by u.ny_day
    having count(u.metric_value) filter (where u.metric_value is not null) > 0
  )
  select
    a.highest_id,
    a.lowest_id,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'day', b.ny_day::text,
            'highest', b.highest,
            'lowest', b.lowest,
            'you', b.you,
            'average', b.average,
            'population_count', b.population_count
          )
          order by b.ny_day
        )
        from bucketed b
      ),
      '[]'::jsonb
    )
  into v_highest, v_lowest, v_points
  from anchors a;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_viewer
    ),
    'data', jsonb_build_object(
      'timeframe', v_timeframe,
      'category', v_category_wire,
      'audience', v_audience,
      'supported', v_supported,
      'metric_format', v_metric_format,
      'highest_profile_id', v_highest,
      'lowest_profile_id', v_lowest,
      'points', coalesce(v_points, '[]'::jsonb)
    )
  );
end;
$$;

comment on function public.rpc_v1_leaderboard_bootstrap(text, text, text, integer, text) is
  'Windowed leaderboard rankings; canonical category slugs; NY timeframe bounds.';

comment on function public.rpc_v1_leaderboard_curve(text, text, text) is
  'Cumulative leaderboard curves for all metrics incl. followers, streak, consistency, payouts; max 180 chart days.';

revoke all on function public.rpc_v1_leaderboard_bootstrap(text, text, text, integer, text) from public;
grant execute on function public.rpc_v1_leaderboard_bootstrap(text, text, text, integer, text) to authenticated;
grant execute on function public.rpc_v1_leaderboard_bootstrap(text, text, text, integer, text) to anon;

revoke all on function public.rpc_v1_leaderboard_curve(text, text, text) from public;
grant execute on function public.rpc_v1_leaderboard_curve(text, text, text) to authenticated;
grant execute on function public.rpc_v1_leaderboard_curve(text, text, text) to anon;