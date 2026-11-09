-- Split legacy "NY" into NY AM / NY Lunch / NY PM (America/New_York wall clock).
-- Parity with web `lib/tradingSession.ts` and iOS `TradingSessionLabel`.

create or replace function public.trading_session_from_et(p_ts timestamptz)
returns text
language sql
stable
set search_path = public
as $$
  select case
    when v.t >= 18 * 60 or v.t < 2 * 60 then 'Asia'
    when v.t >= 2 * 60 and v.t < 8 * 60 then 'London'
    when v.t >= 8 * 60 and v.t < 11 * 60 + 30 then 'NY AM'
    when v.t >= 11 * 60 + 30 and v.t < 13 * 60 + 30 then 'NY Lunch'
    when v.t >= 13 * 60 + 30 and v.t < 17 * 60 then 'NY PM'
    when v.t >= 17 * 60 and v.t < 18 * 60 then 'After'
    else null
  end
  from (
    select (
      extract(hour from p_ts at time zone 'America/New_York')::int * 60
      + extract(minute from p_ts at time zone 'America/New_York')::int
    ) as t
  ) v;
$$;

create or replace function public.analytics_dashboard_session_sort_ord(p_label text)
returns int
language sql
immutable
set search_path = public
as $$
  select case trim(coalesce(p_label, ''))
    when 'NY AM' then 1
    when 'NY Lunch' then 2
    when 'NY PM' then 3
    when 'London' then 4
    when 'Asia' then 5
    when 'After' then 6
    else 99
  end;
$$;

create or replace function public.analytics_dashboard_session_label(p_session text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when v = 'ny am' or v = 'new york am' then 'NY AM'
    when v = 'ny lunch' or v = 'new york lunch' or v = 'lunch' then 'NY Lunch'
    when v = 'ny pm' or v = 'new york pm' or v = 'pm' then 'NY PM'
    when position('lunch' in v) > 0 and (position('ny' in v) > 0 or position('new york' in v) > 0) then 'NY Lunch'
    when position('pm' in v) > 0 and (position('ny' in v) > 0 or position('new york' in v) > 0) then 'NY PM'
    when position('am' in v) > 0 and (position('ny' in v) > 0 or position('new york' in v) > 0) then 'NY AM'
  when position('london' in v) > 0 or position('ldn' in v) > 0 or position('uk' in v) > 0 then 'London'
    when position('asia' in v) > 0 or position('asian' in v) > 0 or position('tokyo' in v) > 0 then 'Asia'
    when v = 'after' then 'After'
    when position('ny' in v) > 0 or position('new york' in v) > 0 then 'NY AM'
    else null
  end
  from (select lower(trim(coalesce(p_session, ''))) as v) s
  where length(trim(coalesce(p_session, ''))) > 0;
$$;

create or replace function public.profile_statistics_session_breakdown_for_mode(
  p_profile_id uuid,
  p_mode text
)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with labeled as (
    select public.analytics_dashboard_session_label(b.session_raw) as label
    from public.profile_statistics_public_trades(p_profile_id) b
    where public.profile_statistics_trade_matches_mode(p_mode, b.acct_mode)
      and public.analytics_dashboard_session_label(b.session_raw) is not null
  ),
  counts as (
    select label, count(*)::int as cnt
    from labeled
    group by 1
  ),
  total as (
    select coalesce(sum(cnt), 0)::int as t from counts
  )
  select jsonb_build_object(
    'session_total', (select t from total),
    'session_breakdown', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'label', c.label,
            'count', c.cnt,
            'pct', case when total.t > 0 then (c.cnt::float / total.t::float) * 100 else 0 end
          )
          order by public.analytics_dashboard_session_sort_ord(c.label)
        )
        from counts c
        cross join total
      ),
      '[]'::jsonb
    )
  );
$$;

-- Reclassify stored sessions from entry timestamps (DST-aware via America/New_York).
update public.trades t
set session = public.trading_session_from_et(ts.parsed)
from (
  select
    id,
    public.analytics_parse_trade_timestamp(entry_time) as parsed
  from public.trades
) ts
where t.id = ts.id
  and ts.parsed is not null
  and public.trading_session_from_et(ts.parsed) is not null;

-- Patch profile statistics RPC session breakdown (uses helper above).
create or replace function public.rpc_v1_profile_statistics_bootstrap(
  p_profile_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_viewer uuid := auth.uid();
  v_can_view boolean := false;
  v_modes jsonb := '{}'::jsonb;
  v_mode text;
  v_mode_list text[] := array['all', 'eval', 'funded', 'live', 'sim', 'backtest'];
  v_total integer := 0;
  v_wins integer := 0;
  v_loss_count integer := 0;
  v_long_trades integer := 0;
  v_total_pnl numeric := 0;
  v_gross_wins numeric := 0;
  v_gross_losses numeric := 0;
  v_biggest_win numeric := 0;
  v_biggest_loss numeric := null;
  v_win_rate numeric := null;
  v_profit_factor numeric := null;
  v_average_winner numeric := null;
  v_average_loser numeric := null;
  v_profit_per_trade numeric := null;
  v_current_equity numeric := 0;
  v_equity jsonb := '[]'::jsonb;
  v_running numeric := 0;
  v_idx integer := 0;
  v_max_win_streak integer := 0;
  v_max_loss_streak integer := 0;
  v_cur_win integer := 0;
  v_cur_loss integer := 0;
  v_pnl numeric;
  v_session_total integer := 0;
  v_session_rows jsonb := '[]'::jsonb;
  v_session_bundle jsonb;
  rec record;
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
      'data', jsonb_build_object('modes', '{}'::jsonb)
    );
  end if;

  foreach v_mode in array v_mode_list loop
    v_total := 0;
    v_wins := 0;
    v_loss_count := 0;
    v_long_trades := 0;
    v_total_pnl := 0;
    v_gross_wins := 0;
    v_gross_losses := 0;
    v_biggest_win := 0;
    v_biggest_loss := null;
    v_win_rate := null;
    v_profit_factor := null;
    v_average_winner := null;
    v_average_loser := null;
    v_profit_per_trade := null;
    v_current_equity := 0;
    v_equity := '[]'::jsonb;
    v_running := 0;
    v_idx := 0;
    v_max_win_streak := 0;
    v_max_loss_streak := 0;
    v_cur_win := 0;
    v_cur_loss := 0;

    select
      count(*)::integer,
      count(*) filter (where coalesce(b.pnl, 0) > 0)::integer,
      count(*) filter (where coalesce(b.pnl, 0) < 0)::integer,
      count(*) filter (where b.is_long)::integer,
      coalesce(sum(coalesce(b.pnl, 0)), 0),
      coalesce(sum(b.pnl) filter (where coalesce(b.pnl, 0) > 0), 0),
      coalesce(sum(b.pnl) filter (where coalesce(b.pnl, 0) < 0), 0),
      coalesce(max(b.pnl), 0),
      min(b.pnl) filter (where coalesce(b.pnl, 0) < 0)
    into
      v_total, v_wins, v_loss_count, v_long_trades,
      v_total_pnl, v_gross_wins, v_gross_losses,
      v_biggest_win, v_biggest_loss
    from public.profile_statistics_public_trades(p_profile_id) b
    where public.profile_statistics_trade_matches_mode(v_mode, b.acct_mode);

    if v_total > 0 then
      v_win_rate := round(v_wins::numeric / v_total::numeric, 8);
      v_profit_per_trade := round(v_total_pnl / v_total::numeric, 8);
    end if;
    if v_gross_losses < 0 then
      v_profit_factor := round(v_gross_wins / abs(v_gross_losses), 8);
    end if;
    if v_wins > 0 then
      v_average_winner := round(v_gross_wins / v_wins::numeric, 8);
    end if;
    if v_loss_count > 0 then
      v_average_loser := round(v_gross_losses / v_loss_count::numeric, 8);
    end if;

    for rec in
      select b.pnl, b.created_at, b.trade_id
      from public.profile_statistics_public_trades(p_profile_id) b
      where public.profile_statistics_trade_matches_mode(v_mode, b.acct_mode)
      order by b.created_at asc, b.trade_id asc
    loop
      v_running := v_running + coalesce(rec.pnl, 0);
      v_equity := v_equity || jsonb_build_array(
        jsonb_build_object(
          'index', v_idx,
          'equity', v_running,
          'date', to_char(rec.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
        )
      );
      v_idx := v_idx + 1;
      v_current_equity := v_running;

      v_pnl := coalesce(rec.pnl, 0);
      if v_pnl > 0 then
        v_cur_win := v_cur_win + 1;
        v_cur_loss := 0;
      elsif v_pnl < 0 then
        v_cur_loss := v_cur_loss + 1;
        v_cur_win := 0;
      else
        v_cur_win := 0;
        v_cur_loss := 0;
      end if;
      if v_cur_win > v_max_win_streak then v_max_win_streak := v_cur_win; end if;
      if v_cur_loss > v_max_loss_streak then v_max_loss_streak := v_cur_loss; end if;
    end loop;

    v_session_bundle := public.profile_statistics_session_breakdown_for_mode(p_profile_id, v_mode);
    v_session_total := coalesce((v_session_bundle->>'session_total')::int, 0);
    v_session_rows := coalesce(v_session_bundle->'session_breakdown', '[]'::jsonb);

    v_modes := v_modes || jsonb_build_object(
      v_mode,
      jsonb_build_object(
        'filtered_trade_count', v_total,
        'win_rate', v_win_rate,
        'profit_factor', v_profit_factor,
        'average_winner', v_average_winner,
        'average_loser', v_average_loser,
        'profit_per_trade', v_profit_per_trade,
        'biggest_win', v_biggest_win,
        'biggest_loss', v_biggest_loss,
        'long_trades', v_long_trades,
        'max_win_streak', v_max_win_streak,
        'max_loss_streak', v_max_loss_streak,
        'session_total', v_session_total,
        'session_breakdown', v_session_rows,
        'current_equity', v_current_equity,
        'equity_data', v_equity
      )
    );
  end loop;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'found', true,
      'server_time', v_server_time,
      'viewer_id', v_viewer
    ),
    'data', jsonb_build_object(
      'profile_id', p_profile_id,
      'modes', v_modes
    )
  );
end;
$$;

-- Dashboard v3 session ordering (sort keys for NY AM/Lunch/PM)
create or replace function public.analytics_dashboard_distributions_block(
  p_user_id uuid,
  p_start date,
  p_end date,
  p_account_id uuid default null
)
returns jsonb
language sql
stable
set search_path = public
as $$
  with scoped as (
    select
      t.*,
      coalesce(t.pnl, 0)::numeric as pnl_n,
      public.analytics_calendar_day(t.entry_time, t.exit_time, t.created_at) as cal_day,
      public.analytics_parse_trade_timestamp(t.entry_time) as entry_ts,
      public.analytics_realized_sort_ts(t.entry_time, t.exit_time, t.created_at) as sort_ts
    from public.trades t
    where t.user_id = p_user_id
      and public.analytics_dashboard_trade_in_scope(t, p_account_id)
  ),
  in_range as (
    select *
    from scoped
    where cal_day between p_start and p_end
  ),
  session_stats as (
    select
      public.analytics_dashboard_session_label(session) as label,
      count(*)::int as trade_count,
      coalesce(sum(pnl_n), 0) as net_pnl,
      count(*) filter (where pnl_n > 0)::int as wins,
      count(*) filter (where pnl_n < 0)::int as losses
    from in_range
    where public.analytics_dashboard_session_label(session) is not null
    group by 1
  ),
  session_total as (
    select coalesce(sum(trade_count), 0)::int as total from session_stats
  ),
  sessions_json as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'label', ss.label,
          'count', ss.trade_count,
          'trade_count', ss.trade_count,
          'net_pnl', ss.net_pnl,
          'wins', ss.wins,
          'losses', ss.losses,
          'win_rate',
            case
              when ss.trade_count > 0
                then round((ss.wins::numeric / ss.trade_count) * 100, 4)
              else 0
            end,
          'pct',
            case
              when st.total > 0
                then round((ss.trade_count::numeric / st.total) * 100, 6)
              else 0
            end
        )
        order by public.analytics_dashboard_session_sort_ord(ss.label)
      ),
      '[]'::jsonb
    ) as sessions
    from session_stats ss
    cross join session_total st
  ),
  symbol_stats as (
    select
      coalesce(nullif(trim(ticker), ''), 'Unknown') as ticker,
      count(*)::int as trades,
      coalesce(sum(pnl_n), 0) as net_pnl,
      count(*) filter (where pnl_n > 0)::int as wins,
      coalesce(sum(nullif(trim(coalesce(rr::text, '')), '')::numeric) filter (
        where nullif(trim(coalesce(rr::text, '')), '') is not null
      ), 0) as sum_rr,
      count(*) filter (
        where nullif(trim(coalesce(rr::text, '')), '') is not null
      )::int as rr_count
    from in_range
    group by 1
  ),
  symbols_json as (
    select coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'ticker', s.ticker,
            'trades', s.trades,
            'net_pnl', s.net_pnl,
            'wins', s.wins,
            'win_rate',
              case when s.trades > 0 then round((s.wins::numeric / s.trades) * 100, 4) else 0 end,
            'avg_rr',
              case when s.rr_count > 0 then round(s.sum_rr / s.rr_count, 6) else null end
          )
          order by s.net_pnl desc
        )
        from (
          select * from symbol_stats order by net_pnl desc limit 12
        ) s
      ),
      '[]'::jsonb
    ) as symbols
  ),
  daily_agg as (
    select cal_day, sum(pnl_n) as day_pnl
    from in_range
    group by cal_day
  ),
  daily_json as (
    select case
      when (select count(*) from daily_agg) = 0 then null
      else jsonb_build_object(
        'best_day_pnl', (select max(day_pnl) from daily_agg),
        'worst_day_pnl', (select min(day_pnl) from daily_agg),
        'avg_day_pnl', (select round(avg(day_pnl), 6) from daily_agg),
        'consistency_pct',
          round(
            (
              (select count(*)::numeric from daily_agg where day_pnl > 0)
              / nullif((select count(*) from daily_agg), 0)
            ) * 100,
            4
          ),
        'trading_days', (select count(*)::int from daily_agg)
      )
    end as daily
  ),
  weekday_pnl as (
    select
      extract(dow from (entry_ts at time zone 'America/New_York'))::int as dow,
      sum(pnl_n) as pnl
    from in_range
    where entry_ts is not null
    group by 1
  ),
  weekday_bars as (
    select coalesce(
      jsonb_agg(jsonb_build_object('label', d.label, 'value', coalesce(w.pnl, 0)) order by d.ord),
      '[]'::jsonb
    ) as bars
    from (
      values (1, 'Mon', 0), (2, 'Tue', 1), (3, 'Wed', 2), (4, 'Thu', 3), (5, 'Fri', 4)
    ) as d(dow, label, ord)
    left join weekday_pnl w on w.dow = d.dow
  ),
  weekday_heatmap as (
    select coalesce(
      jsonb_agg(jsonb_build_object('label', d.label, 'value', coalesce(w.pnl, 0)) order by d.ord),
      '[]'::jsonb
    ) as heatmap
    from (
      values
        (1, 'Mon', 0), (2, 'Tue', 1), (3, 'Wed', 2), (4, 'Thu', 3), (5, 'Fri', 4),
        (6, 'Sat', 5), (0, 'Sun', 6)
    ) as d(dow, label, ord)
    left join weekday_pnl w on w.dow = d.dow
  ),
  hour_pnl as (
    select
      extract(hour from (entry_ts at time zone 'America/New_York'))::int as hr,
      sum(pnl_n) as pnl
    from in_range
    where entry_ts is not null
    group by 1
  ),
  hour_heatmap as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'label', lpad(hr::text, 2, '0'),
          'value', coalesce((select pnl from hour_pnl h where h.hr = hrs.hr), 0)
        )
        order by hrs.hr
      ),
      '[]'::jsonb
    ) as heatmap
    from generate_series(0, 23) as hrs(hr)
  ),
  hour_bars as (
    select coalesce(
      jsonb_agg(jsonb_build_object('label', lpad(hr::text, 2, '0'), 'value', pnl) order by hr),
      '[]'::jsonb
    ) as bars
    from hour_pnl
  ),
  hour_highlights as (
    select case
      when (select count(*) from hour_pnl) <= 1 then jsonb_build_object(
        'best_hour', null,
        'worst_hour', null,
        'best_pnl', null,
        'worst_pnl', null
      )
      else (
        select jsonb_build_object(
          'best_hour', (select hr from hour_pnl order by pnl desc limit 1),
          'worst_hour', (select hr from hour_pnl order by pnl asc limit 1),
          'best_pnl', (select pnl from hour_pnl order by pnl desc limit 1),
          'worst_pnl', (select pnl from hour_pnl order by pnl asc limit 1)
        )
      )
    end as highlights
  ),
  hold_stats as (
    select
      extract(epoch from (
        coalesce(
          public.analytics_parse_trade_timestamp(exit_time),
          public.analytics_parse_trade_timestamp(entry_time)
        ) - public.analytics_parse_trade_timestamp(entry_time)
      )) as dur,
      pnl_n
    from in_range
    where public.analytics_parse_trade_timestamp(entry_time) is not null
  ),
  hold_filtered as (
    select dur, pnl_n
    from hold_stats
    where dur is not null and dur > 0
  ),
  hold_agg as (
    select
      avg(dur) filter (where true) as avg_all,
      avg(dur) filter (where pnl_n > 0) as avg_win,
      avg(dur) filter (where pnl_n < 0) as avg_loss
    from hold_filtered
  ),
  hold_histogram as (
    select coalesce(
      jsonb_agg(jsonb_build_object('label', label, 'count', cnt) order by ord),
      '[]'::jsonb
    ) as buckets
    from (
      select label, ord, count(*)::int as cnt
      from (
        select
          case
            when dur < 300 then '<5m'
            when dur < 900 then '5–15m'
            when dur < 3600 then '15–60m'
            when dur < 14400 then '1–4h'
            else '4h+'
          end as label,
          case
            when dur < 300 then 1
            when dur < 900 then 2
            when dur < 3600 then 3
            when dur < 14400 then 4
            else 5
          end as ord
        from hold_filtered
      ) b
      group by label, ord
    ) h
  ),
  hold_extremes as (
    select jsonb_build_object(
      'fastest_winner_seconds', (select min(dur) from hold_filtered where pnl_n > 0),
      'fastest_winner_pnl', (select pnl_n from hold_filtered where pnl_n > 0 order by dur asc limit 1),
      'longest_winner_seconds', (select max(dur) from hold_filtered where pnl_n > 0),
      'longest_winner_pnl', (select pnl_n from hold_filtered where pnl_n > 0 order by dur desc limit 1),
      'fastest_loser_seconds', (select min(dur) from hold_filtered where pnl_n < 0),
      'fastest_loser_pnl', (select pnl_n from hold_filtered where pnl_n < 0 order by dur asc limit 1),
      'longest_loser_seconds', (select max(dur) from hold_filtered where pnl_n < 0),
      'longest_loser_pnl', (select pnl_n from hold_filtered where pnl_n < 0 order by dur desc limit 1)
    ) as extremes
  ),
  side_metrics as (
    select
      lower(trim(coalesce(direction, ''))) as side,
      count(*)::int as trades,
      coalesce(sum(pnl_n), 0) as net_pnl,
      count(*) filter (where pnl_n > 0)::int as wins,
      count(*) filter (where pnl_n < 0)::int as losses,
      coalesce(sum(pnl_n) filter (where pnl_n > 0), 0) as gross_profit,
      coalesce(abs(sum(pnl_n) filter (where pnl_n < 0)), 0) as gross_loss,
      max(pnl_n) filter (where pnl_n > 0) as best_trade,
      min(pnl_n) filter (where pnl_n < 0) as worst_trade,
      coalesce(sum(nullif(trim(coalesce(rr::text, '')), '')::numeric), 0) as sum_rr,
      count(*) filter (where nullif(trim(coalesce(rr::text, '')), '') is not null)::int as rr_count
    from in_range
    where lower(trim(coalesce(direction, ''))) in ('long', 'short')
    group by 1
  ),
  long_side as (
    select * from side_metrics where side = 'long'
  ),
  short_side as (
    select * from side_metrics where side = 'short'
  ),
  long_short_detail as (
    select jsonb_build_object(
      'long', (
        select jsonb_build_object(
          'trades', ls.trades,
          'net_pnl', ls.net_pnl,
          'wins', ls.wins,
          'losses', ls.losses,
          'win_rate', case when ls.trades > 0 then round((ls.wins::numeric / ls.trades) * 100, 4) else 0 end,
          'profit_factor', case when ls.gross_loss > 0 then round(ls.gross_profit / ls.gross_loss, 6) else null end,
          'expectancy', case when ls.trades > 0 then round(ls.net_pnl / ls.trades, 6) else null end,
          'avg_rr', case when ls.rr_count > 0 then round(ls.sum_rr / ls.rr_count, 6) else null end,
          'best_trade', ls.best_trade,
          'worst_trade', ls.worst_trade
        )
        from long_side ls
      ),
      'short', (
        select jsonb_build_object(
          'trades', ss.trades,
          'net_pnl', ss.net_pnl,
          'wins', ss.wins,
          'losses', ss.losses,
          'win_rate', case when ss.trades > 0 then round((ss.wins::numeric / ss.trades) * 100, 4) else 0 end,
          'profit_factor', case when ss.gross_loss > 0 then round(ss.gross_profit / ss.gross_loss, 6) else null end,
          'expectancy', case when ss.trades > 0 then round(ss.net_pnl / ss.trades, 6) else null end,
          'avg_rr', case when ss.rr_count > 0 then round(ss.sum_rr / ss.rr_count, 6) else null end,
          'best_trade', ss.best_trade,
          'worst_trade', ss.worst_trade
        )
        from short_side ss
      )
    ) as detail
  ),
  long_short as (
    select
      coalesce((select net_pnl from long_side), 0) as long_pnl,
      coalesce((select net_pnl from short_side), 0) as short_pnl,
      coalesce((select trades from long_side), 0)::int as long_count,
      coalesce((select trades from short_side), 0)::int as short_count
  ),
  strategy_stats as (
    select
      trim(strategy) as strategy,
      count(*)::int as trades,
      coalesce(sum(pnl_n), 0) as net_pnl,
      count(*) filter (where pnl_n > 0)::int as wins
    from in_range
    where length(trim(coalesce(strategy, ''))) > 0
    group by 1
  ),
  strategy_json as (
    select jsonb_build_object(
      'best',
        (
          select jsonb_build_object(
            'strategy', strategy,
            'trades', trades,
            'net_pnl', net_pnl,
            'win_rate', round((wins::numeric / trades) * 100, 4)
          )
          from strategy_stats
          where trades >= 3
          order by net_pnl desc
          limit 1
        ),
      'worst',
        (
          select jsonb_build_object(
            'strategy', strategy,
            'trades', trades,
            'net_pnl', net_pnl,
            'win_rate', round((wins::numeric / trades) * 100, 4)
          )
          from strategy_stats
          where trades >= 3
          order by net_pnl asc
          limit 1
        )
    ) as strategies
  )
  select jsonb_build_object(
    'sessions', (select sessions from sessions_json),
    'symbols', (select symbols from symbols_json),
    'daily', (select daily from daily_json),
    'streaks', public.analytics_dashboard_streak_snapshot(p_user_id, p_start, p_end, p_account_id),
    'weekday_bars', (select bars from weekday_bars),
    'weekday_heatmap', (select heatmap from weekday_heatmap),
    'hour_bars', (select bars from hour_bars),
    'hour_heatmap', (select heatmap from hour_heatmap),
    'hour_highlights', (select highlights from hour_highlights),
    'avg_hold_seconds', (select avg_all from hold_agg),
    'avg_winner_hold_seconds', (select avg_win from hold_agg),
    'avg_loser_hold_seconds', (select avg_loss from hold_agg),
    'hold_histogram', (select buckets from hold_histogram),
    'hold_extremes', (select extremes from hold_extremes),
    'long_short', jsonb_build_array(
      jsonb_build_object('label', 'Long', 'value', (select long_pnl from long_short)),
      jsonb_build_object('label', 'Short', 'value', (select short_pnl from long_short))
    ),
    'long_short_detail', (select detail from long_short_detail),
    'long_trade_count', (select long_count from long_short),
    'short_trade_count', (select short_count from long_short),
    'strategies', (select strategies from strategy_json)
  );
$$;

-- CREATE OR REPLACE above resets SECURITY DEFINER from 20261001174213 (42501 on trades).
do $mig$
declare
  src text;
  updated text;
begin
  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'analytics_dashboard_distributions_block'
    and pg_get_function_identity_arguments(p.oid) =
      'p_user_id uuid, p_start date, p_end date, p_account_id uuid';

  if src is null then
    raise exception 'analytics_dashboard_distributions_block(uuid, date, date, uuid) was not found';
  end if;

  if position('auth.uid() is not distinct from p_user_id' in src) = 0 then
    if position('where t.user_id = p_user_id' in src) = 0 then
      raise exception 'analytics_dashboard_distributions_block trade owner predicate was not found';
    end if;
    updated := replace(
      src,
      'where t.user_id = p_user_id',
      'where t.user_id = p_user_id and auth.uid() is not distinct from p_user_id'
    );
    execute updated;
  end if;
end
$mig$;

alter function public.analytics_dashboard_distributions_block(uuid, date, date, uuid)
  security definer;

alter function public.analytics_dashboard_distributions_block(uuid, date, date, uuid)
  set search_path = public, pg_temp;

revoke all on function public.analytics_dashboard_distributions_block(uuid, date, date, uuid)
  from public, anon;

grant execute on function public.analytics_dashboard_distributions_block(uuid, date, date, uuid)
  to authenticated;
