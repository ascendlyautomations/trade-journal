-- Native leaderboard curve: cumulative metric snapshots by NY calendar day.
-- Reuses bootstrap eligibility, audience filters, and category sort keys.

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
  v_category_raw text := lower(trim(coalesce(p_category, 'pnl')));
  v_category text;
  v_now timestamptz := timezone('utc', now());
  v_cutoff timestamptz;
  v_ytd_start date;
  v_highest uuid;
  v_lowest uuid;
  v_metric_format text := 'currency';
  v_points jsonb := '[]'::jsonb;
  v_supported boolean := true;
begin
  v_category_raw := replace(v_category_raw, '_', '');
  v_category := case v_category_raw
    when 'winrate' then 'win_rate'
    when 'profitfactor' then 'profit_factor'
    when 'profitpercent' then 'profit_percent'
    when 'winstreak' then 'win_streak'
    when 'followers' then 'followers'
    when 'consistency' then 'consistency'
    when 'expectancy' then 'expectancy'
    when 'rr' then 'rr'
  else 'pnl'
  end;

  if v_category in ('win_streak', 'consistency', 'followers') then
    return jsonb_build_object(
      'meta', jsonb_build_object(
        'contract_version', 'v1',
        'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'viewer_id', v_viewer
      ),
      'data', jsonb_build_object(
        'timeframe', v_timeframe,
        'category', v_category,
        'audience', v_audience,
        'supported', false,
        'metric_format', 'currency',
        'highest_profile_id', null,
        'lowest_profile_id', null,
        'points', '[]'::jsonb
      )
    );
  end if;

  case v_category
    when 'pnl', 'expectancy' then v_metric_format := 'currency';
    when 'win_rate', 'profit_percent' then v_metric_format := 'percent';
    when 'profit_factor', 'rr' then v_metric_format := 'ratio';
    else v_metric_format := 'currency';
  end case;

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
    when 'all_time', 'alltime' then
      v_cutoff := null;
    else
      v_cutoff := v_now - interval '30 days';
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
  ranked as (
    select
      ua.user_id as profile_id,
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
        when 'profit_percent' then coalesce(ua.profit_percent, -999999)
        else ua.total_pnl
      end as sort_key
    from scored ua
    inner join public.profiles pr on pr.id = ua.user_id
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
  anchors as (
    select
      (select profile_id from ranked order by sort_key desc, profile_id asc limit 1) as highest_id,
      (select profile_id from ranked order by sort_key asc, profile_id desc limit 1) as lowest_id
  ),
  trade_running as (
    select
      wt.user_id,
      wt.id,
      wt.created_at,
      (wt.created_at at time zone 'America/New_York')::date as ny_day,
      coalesce(wt.pnl, 0)::numeric as pnl,
      wt.rr,
      sum(coalesce(wt.pnl, 0)) over w as cum_pnl,
      count(*) over w as cum_trades,
      sum(case when coalesce(wt.pnl, 0) > 0 then 1 else 0 end) over w as cum_wins,
      sum(case when coalesce(wt.pnl, 0) < 0 then 1 else 0 end) over w as cum_losses,
      coalesce(
        sum(coalesce(wt.pnl, 0)) filter (where coalesce(wt.pnl, 0) > 0) over w,
        0
      )::numeric as cum_gross_wins,
      coalesce(
        sum(coalesce(wt.pnl, 0)) filter (where coalesce(wt.pnl, 0) < 0) over w,
        0
      )::numeric as cum_gross_losses,
      avg(wt.rr) filter (where wt.rr is not null) over w as cum_avg_rr,
      max(wt.pnl) filter (where coalesce(wt.pnl, 0) > 0) over w as cum_biggest_win
    from window_trades wt
  window w as (partition by wt.user_id order by wt.created_at asc nulls last, wt.id asc)
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
  eod_merged as (
    select
      coalesce(t.user_id, d.user_id) as user_id,
      coalesce(t.ny_day, d.ny_day) as ny_day,
      t.cum_pnl,
      t.cum_trades,
      t.cum_wins,
      t.cum_losses,
      t.cum_gross_wins,
      t.cum_gross_losses,
      t.cum_avg_rr,
      t.cum_biggest_win,
      d.trading_days,
      d.profitable_days
    from eod_trade t
    full outer join daily_cum d
      on d.user_id = t.user_id and d.ny_day = t.ny_day
  ),
  day_series as (
    select distinct ny_day
    from eod_merged
    where ny_day is not null
    order by ny_day
  ),
  eligible as (
    select profile_id from ranked
  ),
  user_day_values as (
    select
      ds.ny_day,
      e.profile_id,
      (
        select case v_category
          when 'pnl' then em.cum_pnl
          when 'win_rate' then
            case when em.cum_trades > 0 then em.cum_wins::numeric / em.cum_trades else null end
          when 'rr' then em.cum_avg_rr
          when 'profit_factor' then
            case when em.cum_gross_losses < 0
              then em.cum_gross_wins / abs(em.cum_gross_losses)
              else null
            end
          when 'expectancy' then
            case when em.cum_trades > 0 then
              (em.cum_wins::numeric / em.cum_trades)
                * coalesce(em.cum_gross_wins / nullif(em.cum_wins, 0), 0)
              - (em.cum_losses::numeric / em.cum_trades)
                * coalesce(abs(em.cum_gross_losses) / nullif(em.cum_losses, 0), 0)
            else null end
          when 'profit_percent' then
            case when em.trading_days > 0
              then em.profitable_days::numeric / em.trading_days::numeric * 100
              else null
            end
          else em.cum_pnl
        end
        from eod_merged em
        where em.user_id = e.profile_id
          and em.ny_day <= ds.ny_day
        order by em.ny_day desc
        limit 1
      ) as metric_value
    from day_series ds
    cross join eligible e
  ),
  bucketed as (
    select
      u.ny_day,
      max(u.metric_value) filter (where u.profile_id = a.highest_id) as highest,
      max(u.metric_value) filter (where u.profile_id = a.lowest_id) as lowest,
      max(u.metric_value) filter (where v_viewer is not null and u.profile_id = v_viewer) as you,
      avg(u.metric_value) filter (where u.metric_value is not null) as average,
      count(u.metric_value) filter (where u.metric_value is not null)::integer as population_count
    from user_day_values u
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
      'category', v_category,
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

comment on function public.rpc_v1_leaderboard_curve(text, text, text) is
  'Cumulative leaderboard metric curves (highest, lowest, viewer, average) by NY day. Full eligible ranking picks highest/lowest traders.';

revoke all on function public.rpc_v1_leaderboard_curve(text, text, text) from public;
grant execute on function public.rpc_v1_leaderboard_curve(text, text, text) to authenticated;
grant execute on function public.rpc_v1_leaderboard_curve(text, text, text) to anon;