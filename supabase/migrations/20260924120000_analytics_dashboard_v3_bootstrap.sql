-- Dashboard V3 — aggregate-first bootstrap (no fat trade window).
-- Normal ET civil calendar day semantics; equity ordered by analytics_realized_sort_ts.

create or replace function public.analytics_dashboard_as_of_et()
returns date
language sql
stable
set search_path = public
as $$
  select (now() at time zone 'America/New_York')::date;
$$;

create or replace function public.analytics_dashboard_preset_bounds(
  p_as_of date,
  p_preset text,
  out start_day date,
  out end_day date
)
language plpgsql
immutable
set search_path = public
as $$
begin
  if p_as_of is null then
    start_day := null;
    end_day := null;
    return;
  end if;
  end_day := p_as_of;
  case lower(trim(coalesce(p_preset, '')))
    when 'd7' then
      start_day := p_as_of - 6;
    when 'd30' then
      start_day := p_as_of - 29;
    when 'd90' then
      start_day := p_as_of - 89;
    when 'ytd' then
      start_day := make_date(extract(year from p_as_of)::int, 1, 1);
    when 'all' then
      start_day := '1970-01-01'::date;
    else
      raise exception 'invalid_preset' using errcode = '22023';
  end case;
end;
$$;

create or replace function public.analytics_dashboard_compose_metrics(
  p_trade_count integer,
  p_win_count integer,
  p_loss_count integer,
  p_breakeven_count integer,
  p_net_pnl numeric,
  p_gross_profit numeric,
  p_gross_loss numeric,
  p_long_count integer,
  p_long_pnl numeric,
  p_short_count integer,
  p_short_pnl numeric,
  p_sum_rr numeric,
  p_rr_count integer,
  p_sum_hold_seconds bigint,
  p_hold_count integer,
  p_largest_win numeric,
  p_largest_loss numeric
)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_build_object(
    'trade_count', coalesce(p_trade_count, 0),
    'win_count', coalesce(p_win_count, 0),
    'loss_count', coalesce(p_loss_count, 0),
    'breakeven_count', coalesce(p_breakeven_count, 0),
    'net_pnl', coalesce(p_net_pnl, 0),
    'gross_profit', coalesce(p_gross_profit, 0),
    'gross_loss', coalesce(p_gross_loss, 0),
    'long_count', coalesce(p_long_count, 0),
    'long_pnl', coalesce(p_long_pnl, 0),
    'short_count', coalesce(p_short_count, 0),
    'short_pnl', coalesce(p_short_pnl, 0),
    'sum_rr', coalesce(p_sum_rr, 0),
    'rr_count', coalesce(p_rr_count, 0),
    'sum_hold_seconds', coalesce(p_sum_hold_seconds, 0),
    'hold_count', coalesce(p_hold_count, 0),
    'largest_win', p_largest_win,
    'largest_loss', p_largest_loss
  );
$$;

create or replace function public.analytics_dashboard_metrics_from_daily(
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
  with rows as (
    select s.*
    from public.trade_daily_stats s
    where s.user_id = p_user_id
      and s.calendar_day between p_start and p_end
      and s.mode_effective is distinct from 'backtest'
      and (p_account_id is null or s.account_id is not distinct from p_account_id)
  )
  select public.analytics_dashboard_compose_metrics(
    coalesce(sum(r.trade_count), 0)::integer,
    coalesce(sum(r.win_count), 0)::integer,
    coalesce(sum(r.loss_count), 0)::integer,
    coalesce(sum(r.breakeven_count), 0)::integer,
    coalesce(sum(r.net_pnl), 0),
    coalesce(sum(r.gross_profit), 0),
    coalesce(sum(r.gross_loss), 0),
    coalesce(sum(r.long_count), 0)::integer,
    coalesce(sum(r.long_pnl), 0),
    coalesce(sum(r.short_count), 0)::integer,
    coalesce(sum(r.short_pnl), 0),
    coalesce(sum(r.sum_rr), 0),
    coalesce(sum(r.rr_count), 0)::integer,
    coalesce(sum(r.sum_hold_seconds), 0)::bigint,
    coalesce(sum(r.hold_count), 0)::integer,
    max(r.largest_win),
    min(r.largest_loss)
  )
  from rows r;
$$;

create or replace function public.analytics_dashboard_trade_in_scope(
  p_trade public.trades,
  p_account_id uuid default null
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select
    p_trade.user_id is not null
    and lower(trim(coalesce(p_trade.mode, ''))) is distinct from 'backtest'
    and lower(trim(coalesce(p_trade.account_type, ''))) is distinct from 'backtest'
    and (
      p_account_id is null
      or (
        nullif(trim(coalesce(p_trade.account_id, '')), '') ~* '^[0-9a-f-]{36}$'
        and nullif(trim(p_trade.account_id), '')::uuid is not distinct from p_account_id
      )
    );
$$;

create or replace function public.analytics_dashboard_session_label(p_session text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when position('ny' in v) > 0 or position('new york' in v) > 0 then 'NY'
    when position('london' in v) > 0 or position('ldn' in v) > 0 or position('uk' in v) > 0 then 'London'
    when position('asia' in v) > 0 or position('asian' in v) > 0 or position('tokyo' in v) > 0 then 'Asia'
    else null
  end
  from (select lower(trim(coalesce(p_session, ''))) as v) s;
$$;

create or replace function public.analytics_dashboard_equity_block(
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
  v_result jsonb;
begin
  with scoped as (
    select
      t.id,
      coalesce(t.pnl, 0)::numeric as pnl,
      public.analytics_realized_sort_ts(t.entry_time, t.exit_time, t.created_at) as sort_ts,
      public.analytics_calendar_day(t.entry_time, t.exit_time, t.created_at) as cal_day
    from public.trades t
    where t.user_id = p_user_id
      and public.analytics_dashboard_trade_in_scope(t, p_account_id)
  ),
  in_range as (
    select *
    from scoped s
    where s.cal_day between p_start and p_end
      and s.sort_ts is not null
  ),
  ordered as (
    select
      row_number() over (order by sort_ts asc, id asc) as rn,
      count(*) over () as cnt,
      sort_ts,
      sum(pnl) over (order by sort_ts asc, id asc rows between unbounded preceding and current row) as equity
    from in_range
  ),
  peaks as (
    select
      rn,
      cnt,
      sort_ts,
      equity,
      max(equity) over (order by rn rows between unbounded preceding and current row) as peak
    from ordered
  ),
  dd as (
    select coalesce(max(peak - equity), 0) as max_drawdown
    from peaks
  ),
  points as (
    select
      p.rn,
      to_char(p.sort_ts at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') as t,
      p.equity as v
    from peaks p
    where p.rn = 1
       or p.rn = p.cnt
       or p.rn % greatest(1, ceil(p.cnt::numeric / 366.0)::integer) = 0
    order by p.rn
  )
  select jsonb_build_object(
    'points',
      coalesce(
        (select jsonb_agg(jsonb_build_object('t', t, 'v', v, 'i', rn - 1) order by rn) from points),
        '[]'::jsonb
      ),
    'max_drawdown', (select max_drawdown from dd),
    'current_equity', coalesce((select p.equity from peaks p order by p.rn desc limit 1), 0)
  )
  into v_result;
  return coalesce(v_result, jsonb_build_object('points', '[]'::jsonb, 'max_drawdown', 0, 'current_equity', 0));
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
      public.analytics_parse_trade_timestamp(t.entry_time) as entry_ts
    from public.trades t
    where t.user_id = p_user_id
      and public.analytics_dashboard_trade_in_scope(t, p_account_id)
  ),
  in_range as (
    select *
    from scoped
    where cal_day between p_start and p_end
  ),
  session_counts as (
    select
      public.analytics_dashboard_session_label(session) as label,
      count(*)::int as cnt
    from in_range
    where public.analytics_dashboard_session_label(session) is not null
    group by 1
  ),
  session_total as (
    select coalesce(sum(cnt), 0)::int as total from session_counts
  ),
  sessions_json as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'label', sc.label,
          'count', sc.cnt,
          'pct', case when st.total > 0 then round((sc.cnt::numeric / st.total) * 100, 6) else 0 end
        )
        order by case sc.label when 'NY' then 1 when 'London' then 2 when 'Asia' then 3 else 4 end
      ),
      '[]'::jsonb
    ) as sessions
    from session_counts sc
    cross join session_total st
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
      values
        (1, 'Mon', 0),
        (2, 'Tue', 1),
        (3, 'Wed', 2),
        (4, 'Thu', 3),
        (5, 'Fri', 4)
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
        (1, 'Mon', 0),
        (2, 'Tue', 1),
        (3, 'Wed', 2),
        (4, 'Thu', 3),
        (5, 'Fri', 4),
        (6, 'Sat', 5),
        (0, 'Sun', 6)
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
    select case
      when (select count(*) from hour_pnl) <= 1 then
        (select coalesce(jsonb_agg(jsonb_build_object('label', lpad(hr::text, 2, '0'), 'value', pnl) order by hr), '[]'::jsonb) from hour_pnl)
      else
        (select coalesce(jsonb_agg(jsonb_build_object('label', lpad(hr::text, 2, '0'), 'value', pnl) order by hr), '[]'::jsonb) from hour_pnl)
    end as bars
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
  long_short as (
    select
      coalesce(sum(pnl_n) filter (where lower(trim(coalesce(direction, ''))) = 'long'), 0) as long_pnl,
      coalesce(sum(pnl_n) filter (where lower(trim(coalesce(direction, ''))) = 'short'), 0) as short_pnl,
      count(*) filter (where lower(trim(coalesce(direction, ''))) = 'long')::int as long_count,
      count(*) filter (where lower(trim(coalesce(direction, ''))) = 'short')::int as short_count
    from in_range
  )
  select jsonb_build_object(
    'sessions', (select sessions from sessions_json),
    'weekday_bars', (select bars from weekday_bars),
    'weekday_heatmap', (select heatmap from weekday_heatmap),
    'hour_bars', (select bars from hour_bars),
    'hour_heatmap', (select heatmap from hour_heatmap),
    'avg_hold_seconds', (select avg_all from hold_agg),
    'avg_winner_hold_seconds', (select avg_win from hold_agg),
    'avg_loser_hold_seconds', (select avg_loss from hold_agg),
    'hold_histogram', (select buckets from hold_histogram),
    'long_short', jsonb_build_array(
      jsonb_build_object('label', 'Long', 'value', (select long_pnl from long_short)),
      jsonb_build_object('label', 'Short', 'value', (select short_pnl from long_short))
    ),
    'long_trade_count', (select long_count from long_short),
    'short_trade_count', (select short_count from long_short)
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
  v_sessions jsonb;
  v_trade_count int;
  v_long int;
  v_short int;
  v_best_session jsonb;
  v_best_symbol record;
  v_insights jsonb := '[]'::jsonb;
begin
  v_sessions := (
    public.analytics_dashboard_distributions_block(p_user_id, p_start, p_end, p_account_id)->'sessions'
  );

  select elem
  into v_best_session
  from jsonb_array_elements(v_sessions) elem
  order by (elem->>'pct')::numeric desc
  limit 1;

  if v_best_session is not null and coalesce((v_best_session->>'pct')::numeric, 0) >= 1 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'session',
      'title', 'Protect your best session',
      'body', format(
        'Most of your tagged volume lands in %s (%s%%). Review those setups first, that''s where your process is already concentrated.',
        v_best_session->>'label',
        round((v_best_session->>'pct')::numeric)::text
      ),
      'kind', 'session'
    ));
  end if;

  with scoped as (
    select t.ticker, coalesce(t.pnl, 0)::numeric as pnl_n
    from public.trades t
    where t.user_id = p_user_id
      and public.analytics_dashboard_trade_in_scope(t, p_account_id)
      and public.analytics_calendar_day(t.entry_time, t.exit_time, t.created_at) between p_start and p_end
  ),
  sym as (
    select
      coalesce(nullif(trim(ticker), ''), 'Unknown') as symbol,
      sum(pnl_n) as pnl,
      count(*)::int as cnt
    from scoped
    group by 1
  )
  select *
  into v_best_symbol
  from sym
  where cnt >= 3
  order by (pnl / cnt) desc
  limit 1;

  if v_best_symbol is not null then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'symbol',
      'title', 'Lean into your edge market',
      'body', format(
        '%s is your strongest average outcome over %s trades. Size carefully there and journal what you''re doing differently.',
        v_best_symbol.symbol,
        v_best_symbol.cnt
      ),
      'kind', 'symbol'
    ));
  end if;

  select
    count(*) filter (where lower(trim(coalesce(direction, ''))) = 'long')::int,
    count(*) filter (where lower(trim(coalesce(direction, ''))) = 'short')::int,
    count(*)::int
  into v_long, v_short, v_trade_count
  from public.trades t
  where t.user_id = p_user_id
    and public.analytics_dashboard_trade_in_scope(t, p_account_id)
    and public.analytics_calendar_day(t.entry_time, t.exit_time, t.created_at) between p_start and p_end;

  if v_trade_count >= 5 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'direction',
      'title', 'Check your directional bias',
      'body', format(
        'You''re taking more %s trades (%s of %s). Confirm that matches your plan, bias without intent becomes drift.',
        case when v_long >= v_short then 'long' else 'short' end,
        greatest(v_long, v_short),
        v_trade_count
      ),
      'kind', 'direction'
    ));
  end if;

  return v_insights;
end;
$$;

create or replace function public.analytics_dashboard_preset_bundle(
  p_user_id uuid,
  p_preset text,
  p_as_of date,
  p_account_id uuid default null
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_start date;
  v_end date;
begin
  select b.start_day, b.end_day into v_start, v_end
  from public.analytics_dashboard_preset_bounds(p_as_of, p_preset) b;

  return jsonb_build_object(
    'preset', p_preset,
    'start', v_start,
    'end', v_end,
    'metrics', public.analytics_dashboard_metrics_from_daily(p_user_id, v_start, v_end, p_account_id),
    'equity', public.analytics_dashboard_equity_block(p_user_id, v_start, v_end, p_account_id),
    'distributions', public.analytics_dashboard_distributions_block(p_user_id, v_start, v_end, p_account_id),
    'insights', public.analytics_dashboard_insights_block(p_user_id, v_start, v_end, p_account_id)
  );
end;
$$;

create or replace function public.rpc_v1_analytics_dashboard_bootstrap_v3()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_as_of date;
  v_revision bigint;
  v_presets text[] := array['d7', 'd30', 'd90', 'ytd', 'all'];
  v_preset text;
  v_scopes jsonb := '[]'::jsonb;
  v_all_presets jsonb := '{}'::jsonb;
  v_acct record;
  v_acct_presets jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  v_as_of := public.analytics_dashboard_as_of_et();

  select coalesce(u.revision, 0)
  into v_revision
  from public.user_analytics_state u
  where u.user_id = v_uid;

  foreach v_preset in array v_presets loop
    v_all_presets := v_all_presets || jsonb_build_object(
      v_preset,
      public.analytics_dashboard_preset_bundle(v_uid, v_preset, v_as_of, null)
    );
  end loop;

  v_scopes := v_scopes || jsonb_build_array(jsonb_build_object(
    'account_id', null,
    'presets', v_all_presets
  ));

  for v_acct in
    select a.id
    from public.accounts a
    where a.user_id = v_uid
    order by a.created_at asc nulls last, a.id asc
  loop
    v_acct_presets := '{}'::jsonb;
    foreach v_preset in array v_presets loop
      v_acct_presets := v_acct_presets || jsonb_build_object(
        v_preset,
        public.analytics_dashboard_preset_bundle(v_uid, v_preset, v_as_of, v_acct.id)
      );
    end loop;
    v_scopes := v_scopes || jsonb_build_array(jsonb_build_object(
      'account_id', v_acct.id,
      'presets', v_acct_presets
    ));
  end loop;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'revision', coalesce(v_revision, 0),
      'as_of_et', v_as_of,
      'payout_total', (
        select coalesce(sum(a.value_numeric), 0)
        from public.achievements a
        where a.user_id = v_uid
          and coalesce(a.is_public, false) = true
          and lower(trim(coalesce(a.achievement_type, ''))) in (
            'prop_firm_payout',
            'live_trading_payout',
            'payout'
          )
      ),
      'accounts', (
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'id', a.id,
              'account_number', a.account_number,
              'name', a.name,
              'account_size', a.account_size,
              'mode', a.mode,
              'category', a.category,
              'is_active', coalesce(a.is_active, true),
              'can_add_trades', a.can_add_trades,
              'note', a.note,
              'consistency', a.consistency,
              'max_drawdown', a.max_drawdown,
              'daily_drawdown', a.daily_drawdown,
              'profit_target', a.profit_target,
              'winning_days', a.winning_days,
              'winning_day_threshold', a.winning_day_threshold,
              'show_in_account_dropdowns', coalesce(a.show_in_account_dropdowns, true),
              'custom_public_status', a.custom_public_status,
              'payout_drawdown_behavior', a.payout_drawdown_behavior,
              'remember_payout_drawdown_behavior', a.remember_payout_drawdown_behavior
            )
            order by a.created_at asc nulls last, a.id asc
          ),
          '[]'::jsonb
        )
        from public.accounts a
        where a.user_id = v_uid
      ),
      'scopes', v_scopes
    )
  );
end;
$$;

comment on function public.rpc_v1_analytics_dashboard_bootstrap_v3() is
  'Dashboard V3 aggregate bootstrap — preset summaries, equity (analytics_realized_sort_ts), distributions; no trade window.';

revoke all on function public.rpc_v1_analytics_dashboard_bootstrap_v3() from public;
grant execute on function public.rpc_v1_analytics_dashboard_bootstrap_v3() to authenticated;
