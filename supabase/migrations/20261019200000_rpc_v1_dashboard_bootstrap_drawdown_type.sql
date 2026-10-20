-- Dashboard bootstrap: expose accounts.drawdown_type alongside max_drawdown (Live personal drawdown).

create or replace function public.rpc_v1_dashboard_bootstrap(
  p_account_id uuid default null,
  p_trade_limit integer default 500
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_limit integer := greatest(1, least(coalesce(p_trade_limit, 500), 2000));
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  with ctx as (
    select v_uid as uid, v_limit as lim, p_account_id as account_id
  ),
  scoped_trades as materialized (
    select t.*
    from public.trades t
    cross join ctx
    where t.user_id = ctx.uid
      and (ctx.account_id is null or t.account_id = ctx.account_id::text)
  ),
  live_trades as materialized (
    select st.*
    from scoped_trades st
    where lower(trim(coalesce(st.mode, ''))) is distinct from 'backtest'
      and lower(trim(coalesce(st.account_type, ''))) is distinct from 'backtest'
  ),
  trade_stats as (
    select
      count(*)::integer as total_count,
      min(st.created_at) as oldest_created
    from scoped_trades st
  ),
  trade_window_json as (
    select coalesce(jsonb_agg(row_to_json(w)::jsonb), '[]'::jsonb) as trades
    from (
      select
        st.id,
        st.date,
        st.direction,
        st.pnl,
        st.notes,
        st.created_at,
        st.image_url,
        st.image_display_mode,
        st.ticker,
        st.rr,
        st.points,
        st.session,
        st.account_type,
        st.account_id,
        st.user_id,
        st.account_size,
        st.entry_price,
        st.exit_price,
        st.entry_time,
        st.exit_time,
        st.contracts,
        st.reviewed,
        st.confidence,
        st.emotion,
        st.followed_plan,
        st.mistake_type,
        st.market_condition,
        st.news_event,
        st.timeframe,
        st.psychology_notes,
        st.trade_type,
        st.public_description,
        st.is_pinned,
        st.account_name,
        st.mode,
        st.strategy,
        st.duration_seconds,
        st.duration_text,
        st.is_public,
        st.account_category,
        st.top_confluences,
        st.trade_date,
        st.is_initial_import,
        st.copy_trading_group_id,
        st.trade_mode,
        st.source_account_id,
        st.copied_account_ids
      from scoped_trades st
      order by st.created_at desc nulls last, st.id desc
      limit (select lim from ctx)
    ) w
  ),
  metrics_json as (
    select jsonb_build_object(
      'total_trades', count(*)::integer,
      'wins', count(*) filter (where coalesce(lt.pnl, 0) > 0)::integer,
      'losses', count(*) filter (where coalesce(lt.pnl, 0) < 0)::integer,
      'win_rate', case
        when count(*) = 0 then null
        else round(
          (count(*) filter (where coalesce(lt.pnl, 0) > 0))::numeric
          / count(*)::numeric,
          6
        )
      end,
      'net_pnl', coalesce(sum(lt.pnl), 0),
      'avg_rr', avg(lt.rr),
      'avg_win', avg(lt.pnl) filter (where coalesce(lt.pnl, 0) > 0),
      'avg_loss', avg(lt.pnl) filter (where coalesce(lt.pnl, 0) < 0),
      'biggest_win', max(lt.pnl),
      'biggest_loss', min(lt.pnl)
    ) as metrics
    from live_trades lt
  ),
  equity_json as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object('t', x.ts, 'v', x.equity)
        order by x.rn
      ),
      '[]'::jsonb
    ) as equity
    from (
      select s.rn, s.ts, s.equity
      from (
        select
          row_number() over (order by lt.created_at asc nulls last, lt.id asc) as rn,
          count(*) over () as cnt,
          to_char(lt.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') as ts,
          sum(coalesce(lt.pnl, 0)) over (
            order by lt.created_at asc nulls last, lt.id asc
            rows between unbounded preceding and current row
          ) as equity
        from live_trades lt
      ) s
      where s.rn = 1
         or s.rn = s.cnt
         or s.rn % greatest(1, ceil(s.cnt::numeric / 366.0)::integer) = 0
    ) x
  ),
  accounts_json as (
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
          'drawdown_type', a.drawdown_type,
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
    ) as accounts
    from public.accounts a
    cross join ctx
    where a.user_id = ctx.uid
      and (ctx.account_id is null or a.id = ctx.account_id)
  ),
  payout_json as (
    select coalesce(sum(a.value_numeric), 0) as payout_total
    from public.achievements a
    cross join ctx
    where a.user_id = ctx.uid
      and coalesce(a.is_public, false) = true
      and lower(trim(coalesce(a.achievement_type, ''))) in (
        'prop_firm_payout',
        'live_trading_payout',
        'payout'
      )
  ),
  recent_json as (
    select coalesce(jsonb_agg(elem), '[]'::jsonb) as recent
    from (
      select elem
      from trade_window_json tw,
        jsonb_array_elements(tw.trades) with ordinality as t(elem, ord)
      where ord <= 5
    ) s
  )
  select jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object(
      'accounts', aj.accounts,
      'trade_window', tw.trades,
      'trade_window_meta', jsonb_build_object(
        'limit', v_limit,
        'returned', jsonb_array_length(tw.trades),
        'history_complete',
          (ts.total_count <= jsonb_array_length(tw.trades))
          or (jsonb_array_length(tw.trades) < v_limit),
        'total_trade_count', ts.total_count,
        'oldest_created_at', case
          when ts.oldest_created is null then null
          else to_char(ts.oldest_created, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        end,
        'next_cursor', null
      ),
      'metrics', mj.metrics,
      'equity_points', ej.equity,
      'payout_total', pj.payout_total,
      'recent_trades', rj.recent
    )
  )
  into v_result
  from ctx
  cross join trade_stats ts
  cross join trade_window_json tw
  cross join metrics_json mj
  cross join equity_json ej
  cross join accounts_json aj
  cross join payout_json pj
  cross join recent_json rj;

  return v_result;
end;
$$;

comment on function public.rpc_v1_dashboard_bootstrap(uuid, integer) is
  'Dashboard bootstrap — accounts include drawdown_type; trade_window includes image_display_mode.';
