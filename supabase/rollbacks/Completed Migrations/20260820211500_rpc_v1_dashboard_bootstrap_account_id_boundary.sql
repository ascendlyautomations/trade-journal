-- Backend V2: keep p_account_id as uuid (canonical account identity = accounts.id).
-- trades.account_id is legacy text; compare with p_account_id::text at that boundary only.
-- Do not cast trades.account_id to uuid (invalid legacy values exist).

create or replace function public.rpc_v1_dashboard_bootstrap(
  p_account_id uuid default null,
  p_trade_limit integer default 500
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_trade_limit, 500), 2000));
  v_accounts jsonb := '[]'::jsonb;
  v_trades jsonb := '[]'::jsonb;
  v_recent jsonb := '[]'::jsonb;
  v_equity jsonb := '[]'::jsonb;
  v_metrics jsonb := '{}'::jsonb;
  v_trade_count integer := 0;
  v_window_count integer := 0;
  v_history_complete boolean := true;
  v_payout_total numeric := null;
  v_oldest_created timestamp without time zone := null;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

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
        'winning_day_threshold', a.winning_day_threshold
      )
      order by a.created_at asc nulls last, a.id asc
    ),
    '[]'::jsonb
  )
  into v_accounts
  from public.accounts a
  where a.user_id = v_uid
    and (p_account_id is null or a.id = p_account_id);

  select count(*)::integer
  into v_trade_count
  from public.trades t
  where t.user_id = v_uid
    and (p_account_id is null or t.account_id = p_account_id::text);

  select coalesce(jsonb_agg(row_to_json(q)::jsonb), '[]'::jsonb)
  into v_trades
  from (
    select
      t.id,
      t.date,
      t.direction,
      t.pnl,
      t.notes,
      t.created_at,
      t.image_url,
      t.ticker,
      t.rr,
      t.points,
      t.session,
      t.account_type,
      t.account_id,
      t.user_id,
      t.account_size,
      t.entry_price,
      t.exit_price,
      t.entry_time,
      t.exit_time,
      t.contracts,
      t.reviewed,
      t.confidence,
      t.emotion,
      t.followed_plan,
      t.mistake_type,
      t.market_condition,
      t.news_event,
      t.timeframe,
      t.psychology_notes,
      t.trade_type,
      t.public_description,
      t.is_pinned,
      t.account_name,
      t.mode,
      t.strategy,
      t.duration_seconds,
      t.duration_text,
      t.is_public,
      t.account_category,
      t.top_confluences,
      t.trade_date,
      t.is_initial_import,
      t.copy_trading_group_id,
      t.trade_mode,
      t.source_account_id,
      t.copied_account_ids
    from public.trades t
    where t.user_id = v_uid
      and (p_account_id is null or t.account_id = p_account_id::text)
    order by t.created_at desc nulls last, t.id desc
    limit v_limit
  ) q;

  v_window_count := jsonb_array_length(v_trades);
  v_history_complete := (v_trade_count <= v_window_count) or (v_window_count < v_limit);

  select coalesce(jsonb_agg(elem), '[]'::jsonb)
  into v_recent
  from (
    select elem
    from jsonb_array_elements(v_trades) with ordinality as t(elem, ord)
    where ord <= 5
  ) s;

  select jsonb_build_object(
    'total_trades', count(*)::integer,
    'wins', count(*) filter (where coalesce(t.pnl, 0) > 0)::integer,
    'losses', count(*) filter (where coalesce(t.pnl, 0) < 0)::integer,
    'win_rate', case
      when count(*) = 0 then null
      else round(
        (count(*) filter (where coalesce(t.pnl, 0) > 0))::numeric
        / count(*)::numeric,
        6
      )
    end,
    'net_pnl', coalesce(sum(t.pnl), 0),
    'avg_rr', avg(t.rr),
    'avg_win', avg(t.pnl) filter (where coalesce(t.pnl, 0) > 0),
    'avg_loss', avg(t.pnl) filter (where coalesce(t.pnl, 0) < 0),
    'biggest_win', max(t.pnl),
    'biggest_loss', min(t.pnl)
  )
  into v_metrics
  from public.trades t
  where t.user_id = v_uid
    and (p_account_id is null or t.account_id = p_account_id::text)
    and lower(trim(coalesce(t.mode, ''))) is distinct from 'backtest'
    and lower(trim(coalesce(t.account_type, ''))) is distinct from 'backtest';

  select coalesce(
    jsonb_agg(
      jsonb_build_object('t', x.ts, 'v', x.equity)
      order by x.rn
    ),
    '[]'::jsonb
  )
  into v_equity
  from (
    select s.rn, s.ts, s.equity
    from (
      select
        row_number() over (order by t.created_at asc nulls last, t.id asc) as rn,
        count(*) over () as cnt,
        to_char(t.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') as ts,
        sum(coalesce(t.pnl, 0)) over (
          order by t.created_at asc nulls last, t.id asc
          rows between unbounded preceding and current row
        ) as equity
      from public.trades t
      where t.user_id = v_uid
        and (p_account_id is null or t.account_id = p_account_id::text)
        and lower(trim(coalesce(t.mode, ''))) is distinct from 'backtest'
        and lower(trim(coalesce(t.account_type, ''))) is distinct from 'backtest'
    ) s
    where s.rn = 1
       or s.rn = s.cnt
       or s.rn % greatest(1, ceil(s.cnt::numeric / 366.0)::integer) = 0
  ) x;

  select coalesce(sum(p.payout_amount), 0)
  into v_payout_total
  from public.account_payout_cycles p
  where p.user_id = v_uid
    and (p_account_id is null or p.account_id = p_account_id);

  select min(t.created_at)
  into v_oldest_created
  from public.trades t
  where t.user_id = v_uid
    and (p_account_id is null or t.account_id = p_account_id::text);

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object(
      'accounts', v_accounts,
      'trade_window', v_trades,
      'trade_window_meta', jsonb_build_object(
        'limit', v_limit,
        'returned', v_window_count,
        'history_complete', v_history_complete,
        'total_trade_count', v_trade_count,
        'oldest_created_at', case
          when v_oldest_created is null then null
          else to_char(v_oldest_created, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        end,
        'next_cursor', null
      ),
      'metrics', v_metrics,
      'equity_points', v_equity,
      'payout_total', v_payout_total,
      'recent_trades', v_recent
    )
  );
end;
$$;

comment on function public.rpc_v1_dashboard_bootstrap(uuid, integer) is
  'Backend V2 Dashboard bootstrap — accounts + trade window + metrics/equity. p_account_id uuid; trades.account_id compared as text.';

-- Preserve existing EXECUTE grants (authenticated / anon / service_role).
