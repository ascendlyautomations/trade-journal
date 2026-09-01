-- Phase 2: Calendar month bootstrap — owner accounts + bounded entry_time trade window.

create or replace function public.rpc_v1_calendar_bootstrap(
  p_year int,
  p_month int,
  p_account_id uuid default null,
  p_entry_from timestamptz default null,
  p_entry_to timestamptz default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_accounts jsonb := '[]'::jsonb;
  v_trades jsonb := '[]'::jsonb;
  v_net_pnl numeric := 0;
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
  into v_accounts
  from public.accounts a
  where a.user_id = v_uid;

  with scoped as (
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
      and coalesce(lower(trim(t.mode)), '') <> 'backtest'
      and (p_entry_from is null or t.entry_time >= p_entry_from)
      and (p_entry_to is null or t.entry_time <= p_entry_to)
      and (
        p_account_id is null
        or nullif(trim(t.account_id), '') = p_account_id::text
      )
    order by t.entry_time asc nulls last, t.created_at asc
    limit 500
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'date', s.date,
          'direction', s.direction,
          'pnl', s.pnl,
          'notes', s.notes,
          'created_at', to_char(s.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'image_url', s.image_url,
          'ticker', s.ticker,
          'rr', s.rr,
          'points', s.points,
          'session', s.session,
          'account_type', s.account_type,
          'account_id', s.account_id,
          'user_id', s.user_id,
          'account_size', s.account_size,
          'entry_price', s.entry_price,
          'exit_price', s.exit_price,
          'entry_time', to_char(s.entry_time at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'exit_time', to_char(s.exit_time at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'contracts', s.contracts,
          'reviewed', s.reviewed,
          'confidence', s.confidence,
          'emotion', s.emotion,
          'followed_plan', s.followed_plan,
          'mistake_type', s.mistake_type,
          'market_condition', s.market_condition,
          'news_event', s.news_event,
          'timeframe', s.timeframe,
          'psychology_notes', s.psychology_notes,
          'trade_type', s.trade_type,
          'public_description', s.public_description,
          'is_pinned', s.is_pinned,
          'account_name', s.account_name,
          'mode', s.mode,
          'strategy', s.strategy,
          'duration_seconds', s.duration_seconds,
          'duration_text', s.duration_text,
          'is_public', s.is_public,
          'account_category', s.account_category,
          'top_confluences', s.top_confluences,
          'trade_date', s.trade_date,
          'is_initial_import', s.is_initial_import,
          'copy_trading_group_id', s.copy_trading_group_id,
          'trade_mode', s.trade_mode,
          'source_account_id', s.source_account_id,
          'copied_account_ids', s.copied_account_ids
        )
      ),
      '[]'::jsonb
    ),
    coalesce(sum(coalesce(s.pnl, 0)), 0)
  into v_trades, v_net_pnl
  from scoped s;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'year', p_year,
      'month', p_month,
      'accounts', v_accounts,
      'trades', v_trades,
      'metrics_month', jsonb_build_object('net_pnl', v_net_pnl)
    )
  );
end;
$$;

revoke all on function public.rpc_v1_calendar_bootstrap(int, int, uuid, timestamptz, timestamptz) from public;
grant execute on function public.rpc_v1_calendar_bootstrap(int, int, uuid, timestamptz, timestamptz) to authenticated;

comment on function public.rpc_v1_calendar_bootstrap is
  'Phase 2 Calendar bootstrap — full owner accounts + bounded month entry_time trade window.';
