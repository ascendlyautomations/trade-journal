-- Fix PL/pgSQL CTE scope in analytics_dashboard_insights_block (42P01 relation "sym" does not exist).
-- CTEs are statement-scoped; the second SELECT INTO could not see `sym`. RR counts had the same bug.

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
