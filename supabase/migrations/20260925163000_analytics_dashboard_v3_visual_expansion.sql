-- Dashboard V3 distributions + insights expansion for native visual analytics.
-- Extends charts-bundle payload only (same RPCs); no new per-widget endpoints.

create or replace function public.analytics_dashboard_streak_snapshot(
  p_user_id uuid,
  p_start date,
  p_end date,
  p_account_id uuid default null
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  r record;
  v_type text;
  v_cur int := 0;
  v_cur_type text := null;
  v_max_win int := 0;
  v_max_loss int := 0;
  v_temp_type text := null;
  v_temp int := 0;
begin
  for r in
    select
      case
        when coalesce(t.pnl, 0)::numeric > 0 then 'win'
        when coalesce(t.pnl, 0)::numeric < 0 then 'loss'
        else 'even'
      end as outcome
    from public.trades t
    where t.user_id = p_user_id
      and public.analytics_dashboard_trade_in_scope(t, p_account_id)
      and public.analytics_calendar_day(t.entry_time, t.exit_time, t.created_at) between p_start and p_end
    order by
      public.analytics_realized_sort_ts(t.entry_time, t.exit_time, t.created_at) asc nulls last,
      t.id asc
  loop
    v_type := r.outcome;
    if v_type = v_temp_type then
      v_temp := v_temp + 1;
    else
      v_temp := 1;
      v_temp_type := v_type;
    end if;
    if v_type = 'win' and v_temp > v_max_win then
      v_max_win := v_temp;
    elsif v_type = 'loss' and v_temp > v_max_loss then
      v_max_loss := v_temp;
    end if;
    v_cur := v_temp;
    v_cur_type := v_temp_type;
  end loop;

  return jsonb_build_object(
    'current_streak', coalesce(v_cur, 0),
    'current_type', v_cur_type,
    'max_win_streak', coalesce(v_max_win, 0),
    'max_loss_streak', coalesce(v_max_loss, 0)
  );
end;
$$;

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
        order by case ss.label when 'NY' then 1 when 'London' then 2 when 'Asia' then 3 else 4 end
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

create or replace function public.analytics_dashboard_insights_block(
  p_user_id uuid,
  p_start date,
  p_end date,
  p_account_id uuid default null
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_dist jsonb;
  v_insights jsonb := '[]'::jsonb;
  v_elem jsonb;
  v_best_session jsonb;
  v_worst_session jsonb;
  v_best_symbol record;
  v_worst_symbol record;
  v_best_strategy jsonb;
  v_worst_strategy jsonb;
  v_long jsonb;
  v_short jsonb;
  v_loss_streak_rate numeric;
  v_low_rr_win numeric;
  v_high_rr_win numeric;
  v_rr_low_count int;
  v_rr_high_count int;
begin
  v_dist := public.analytics_dashboard_distributions_block(p_user_id, p_start, p_end, p_account_id);

  select elem into v_best_session
  from jsonb_array_elements(v_dist->'sessions') elem
  order by (elem->>'net_pnl')::numeric desc nulls last
  limit 1;

  select elem into v_worst_session
  from jsonb_array_elements(v_dist->'sessions') elem
  order by (elem->>'net_pnl')::numeric asc nulls last
  limit 1;

  if v_best_session is not null
     and coalesce((v_best_session->>'trade_count')::int, 0) >= 3
     and coalesce((v_best_session->>'net_pnl')::numeric, 0) > 0 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'session_edge',
      'title', 'Session edge',
      'body', format(
        '%s is your strongest session (%s net P/L across %s trades, %s%% win rate).',
        v_best_session->>'label',
        to_char((v_best_session->>'net_pnl')::numeric, 'FM999,999,990.00'),
        v_best_session->>'trade_count',
        round((v_best_session->>'win_rate')::numeric)::text
      ),
      'kind', 'session'
    ));
  end if;

  select
    elem->>'ticker' as symbol,
    (elem->>'net_pnl')::numeric as pnl,
    (elem->>'trades')::int as cnt
  into v_best_symbol
  from jsonb_array_elements(coalesce(v_dist->'symbols', '[]'::jsonb)) elem
  where coalesce((elem->>'trades')::int, 0) >= 3
  order by ((elem->>'net_pnl')::numeric / nullif((elem->>'trades')::int, 0)) desc nulls last
  limit 1;

  select
    elem->>'ticker' as symbol,
    (elem->>'net_pnl')::numeric as pnl,
    (elem->>'trades')::int as cnt
  into v_worst_symbol
  from jsonb_array_elements(coalesce(v_dist->'symbols', '[]'::jsonb)) elem
  where coalesce((elem->>'trades')::int, 0) >= 3
  order by ((elem->>'net_pnl')::numeric / nullif((elem->>'trades')::int, 0)) asc nulls last
  limit 1;

  if v_best_symbol is not null then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'symbol',
      'title', 'Ticker edge',
      'body', format(
        '%s has your best average outcome ($%s per trade over %s trades).',
        v_best_symbol.symbol,
        to_char(v_best_symbol.pnl / v_best_symbol.cnt, 'FM999,999,990.00'),
        v_best_symbol.cnt
      ),
      'kind', 'symbol'
    ));
  end if;

  if v_worst_symbol is not null and v_worst_symbol.pnl < 0 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'symbol_weak',
      'title', 'Ticker drag',
      'body', format(
        '%s is weighing on results ($%s avg over %s trades). Review size and rules there.',
        v_worst_symbol.symbol,
        to_char(v_worst_symbol.pnl / v_worst_symbol.cnt, 'FM999,999,990.00'),
        v_worst_symbol.cnt
      ),
      'kind', 'symbol'
    ));
  end if;

  v_long := v_dist->'long_short_detail'->'long';
  v_short := v_dist->'long_short_detail'->'short';
  if v_long is not null and v_short is not null
     and coalesce((v_long->>'trades')::int, 0) >= 5
     and coalesce((v_short->>'trades')::int, 0) >= 5 then
    if coalesce((v_long->>'net_pnl')::numeric, 0) > coalesce((v_short->>'net_pnl')::numeric, 0) + 50 then
      v_insights := v_insights || jsonb_build_array(jsonb_build_object(
        'id', 'direction_long',
        'title', 'Direction edge',
        'body', 'Long trades are carrying more net P/L than shorts in this window. Confirm sizing matches your plan on both sides.',
        'kind', 'direction'
      ));
    elsif coalesce((v_short->>'net_pnl')::numeric, 0) > coalesce((v_long->>'net_pnl')::numeric, 0) + 50 then
      v_insights := v_insights || jsonb_build_array(jsonb_build_object(
        'id', 'direction_short',
        'title', 'Direction edge',
        'body', 'Short trades are carrying more net P/L than longs in this window. Confirm sizing matches your plan on both sides.',
        'kind', 'direction'
      ));
    end if;
  end if;

  v_best_strategy := v_dist->'strategies'->'best';
  v_worst_strategy := v_dist->'strategies'->'worst';
  if v_best_strategy is not null and v_best_strategy <> 'null'::jsonb then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'strategy_best',
      'title', 'Strongest setup',
      'body', format(
        '%s is your top strategy ($%s over %s trades, %s%% wins).',
        v_best_strategy->>'strategy',
        to_char((v_best_strategy->>'net_pnl')::numeric, 'FM999,999,990.00'),
        v_best_strategy->>'trades',
        round((v_best_strategy->>'win_rate')::numeric)::text
      ),
      'kind', 'session'
    ));
  end if;

  if v_worst_strategy is not null and v_worst_strategy <> 'null'::jsonb
     and coalesce((v_worst_strategy->>'net_pnl')::numeric, 0) < 0 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'strategy_worst',
      'title', 'Weakest setup',
      'body', format(
        '%s is struggling ($%s over %s trades). Consider tightening rules or reducing size.',
        v_worst_strategy->>'strategy',
        to_char((v_worst_strategy->>'net_pnl')::numeric, 'FM999,999,990.00'),
        v_worst_strategy->>'trades'
      ),
      'kind', 'session'
    ));
  end if;

  with ordered as (
    select
      coalesce(t.pnl, 0)::numeric as pnl_n,
      row_number() over (
        order by public.analytics_realized_sort_ts(t.entry_time, t.exit_time, t.created_at), t.id
      ) as rn
    from public.trades t
    where t.user_id = p_user_id
      and public.analytics_dashboard_trade_in_scope(t, p_account_id)
      and public.analytics_calendar_day(t.entry_time, t.exit_time, t.created_at) between p_start and p_end
  ),
  triple_loss as (
    select o1.rn as start_rn
    from ordered o1
    where (
      select count(*) = 3 and bool_and(o2.pnl_n < 0)
      from ordered o2
      where o2.rn between o1.rn and o1.rn + 2
    )
    order by o1.rn
    limit 1
  )
  select
    (
      select count(*) filter (where pnl_n > 0)::numeric / nullif(count(*), 0)
      from ordered o
      cross join triple_loss t
      where o.rn > t.start_rn + 2 and o.rn <= t.start_rn + 7
    )
  into v_loss_streak_rate
  from triple_loss;

  if v_loss_streak_rate is not null and v_loss_streak_rate < 0.45 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'loss_streak',
      'title', 'After losing streaks',
      'body', format(
        'After 3 consecutive losses, your win rate drops to about %s%% in the next few trades.',
        round(v_loss_streak_rate * 100)::text
      ),
      'kind', 'direction'
    ));
  end if;

  with rr as (
    select
      coalesce(t.pnl, 0)::numeric as pnl_n,
      nullif(trim(coalesce(t.rr::text, '')), '')::numeric as rr
    from public.trades t
    where t.user_id = p_user_id
      and public.analytics_dashboard_trade_in_scope(t, p_account_id)
      and public.analytics_calendar_day(t.entry_time, t.exit_time, t.created_at) between p_start and p_end
  )
  select
    count(*) filter (where rr is not null and rr < 1 and pnl_n > 0)::numeric
      / nullif(count(*) filter (where rr is not null and rr < 1), 0),
    count(*) filter (where rr is not null and rr >= 1 and pnl_n > 0)::numeric
      / nullif(count(*) filter (where rr is not null and rr >= 1), 0),
    count(*) filter (where rr is not null and rr < 1)::int,
    count(*) filter (where rr is not null and rr >= 1)::int
  into v_low_rr_win, v_high_rr_win, v_rr_low_count, v_rr_high_count
  from rr;

  if coalesce(v_high_rr_win, 0) > coalesce(v_low_rr_win, 0) + 0.2
     and coalesce(v_rr_low_count, 0) >= 3
     and coalesce(v_rr_high_count, 0) >= 3 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'rr_threshold',
      'title', 'Risk/reward discipline',
      'body', 'You perform significantly better when RR is at least 1.',
      'kind', 'direction'
    ));
  end if;

  return v_insights;
end;
$$;

comment on function public.analytics_dashboard_distributions_block(uuid, date, date, uuid) is
  'Dashboard V3 chart distributions: sessions P/L, symbols, daily, streaks, direction detail, hold extremes, strategies.';

comment on function public.analytics_dashboard_insights_block(uuid, date, date, uuid) is
  'Dashboard V3 coaching insights derived from distributions and scoped trades.';
