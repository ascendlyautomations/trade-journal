-- DEPRECATED: do not apply if 20261124160000_leaderboard_bootstrap_curve_parity.sql is applied.
-- Corrective replace for rpc_v1_leaderboard_curve (production fix).
-- Performance: elimininate per-(day,user) correlated subqueries; scope trade scans to ranked users.
-- Ranking: highest/lowest only among rankable traders (exclude -999999 sentinel sort keys).
-- Timeframe: NY-local timestamptz cutoffs; all_time via same else-null pattern as bootstrap.

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
  v_category text := lower(trim(coalesce(p_category, 'pnl')));
  v_category_wire text;
  v_now timestamptz := timezone('utc', now());
  v_cutoff timestamptz;
  v_today_end timestamptz;
  v_ytd_start date;
  v_highest uuid;
  v_lowest uuid;
  v_metric_format text := 'currency';
  v_points jsonb := '[]'::jsonb;
  v_supported boolean := true;
  v_ny_now timestamp;
begin
  v_ny_now := v_now at time zone 'America/New_York';

  v_category_wire := case replace(v_category, '_', '')
    when 'winrate' then 'win_rate'
    when 'profitfactor' then 'profit_factor'
    when 'profitpercent' then 'profit_percent'
    when 'winstreak' then 'win_streak'
    when 'followers' then 'followers'
    when 'consistency' then 'consistency'
    when 'expectancy' then 'expectancy'
    when 'rr' then 'rr'
    else coalesce(nullif(v_category, ''), 'pnl')
  end;

  if replace(v_category, '_', '') in ('winstreak', 'consistency', 'followers')
     or v_category in ('win_streak', 'consistency', 'followers')
  then
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
        'supported', false,
        'metric_format', 'currency',
        'highest_profile_id', null,
        'lowest_profile_id', null,
        'points', '[]'::jsonb
      )
    );
  end if;

  case v_category_wire
    when 'pnl', 'expectancy' then v_metric_format := 'currency';
    when 'win_rate', 'profit_percent' then v_metric_format := 'percent';
    when 'profit_factor', 'rr' then v_metric_format := 'ratio';
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
      case
        when coalesce(ds.trading_days, 0) > 0 then
          ds.profitable_days::numeric / ds.trading_days::numeric * 100
        else null
      end as profit_percent
    from window_trades wt
    left join day_stats ds on ds.user_id = wt.user_id
    group by wt.user_id, ds.trading_days, ds.profitable_days
    having count(*) > 0
  ),
  ranked as (
    select
      ua.user_id as profile_id,
      -- Same formulas as rpc_v1_leaderboard_bootstrap; v_category_wire maps iOS slugs (winrate, profitfactor).
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
        when 'profit_percent' then coalesce(ua.profit_percent, -999999)
        else ua.total_pnl
      end as sort_key
    from user_agg ua
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
  rankable as (
    select *
    from ranked
    where sort_key > -999999
  ),
  eligible as (
    select profile_id from ranked
  ),
  anchors as (
    select
      (select profile_id from rankable order by sort_key desc, profile_id asc limit 1) as highest_id,
      (select profile_id from rankable order by sort_key asc, profile_id desc limit 1) as lowest_id
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
      avg(st.rr) filter (where st.rr is not null) over w as cum_avg_rr
    from scoped_trades st
    window w as (partition by st.user_id order by st.created_at asc nulls last, st.id asc)
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
      cum_avg_rr
    from trade_running
    where created_at is not null
    order by user_id, ny_day, created_at desc, id desc
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
        else et.cum_pnl
      end as metric_value
    from eod_trade et
    where v_category_wire <> 'profit_percent'
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
  day_series as (
    select distinct ny_day
    from eod_metrics
    where ny_day is not null
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

comment on function public.rpc_v1_leaderboard_curve(text, text, text) is
  'Cumulative leaderboard curves by NY day. Rankable anchors only; scoped trade scan; security invoker (RLS).';

revoke all on function public.rpc_v1_leaderboard_curve(text, text, text) from public;
grant execute on function public.rpc_v1_leaderboard_curve(text, text, text) to authenticated;
grant execute on function public.rpc_v1_leaderboard_curve(text, text, text) to anon;