-- Calendar V2: owner trade summaries for a single normal analytics calendar day.
-- Day list grain MUST match trade_daily_stats / analytics_calendar_day (no 18:00 rollover).

create or replace function public.rpc_v1_analytics_calendar_day_trades(
  p_calendar_day date,
  p_account_id uuid default null,
  p_mode text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_mode text := nullif(lower(trim(coalesce(p_mode, ''))), '');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_calendar_day is null then
    raise exception 'invalid_calendar_day' using errcode = '22023';
  end if;

  return (
    with state as (
      select coalesce(u.revision, 0) as revision, u.updated_at
      from public.user_analytics_state u
      where u.user_id = v_uid
    ),
    aggregate as (
      select
        coalesce(sum(s.trade_count), 0)::integer as trade_count,
        coalesce(sum(s.win_count), 0)::integer as win_count,
        coalesce(sum(s.loss_count), 0)::integer as loss_count,
        coalesce(sum(s.breakeven_count), 0)::integer as breakeven_count,
        coalesce(sum(s.net_pnl), 0) as net_pnl,
        coalesce(sum(s.gross_profit), 0) as gross_profit,
        coalesce(sum(s.gross_loss), 0) as gross_loss
      from public.trade_daily_stats s
      where s.user_id = v_uid
        and s.calendar_day = p_calendar_day
        and (p_account_id is null or s.account_id is not distinct from p_account_id)
        and (v_mode is null or s.mode_effective = v_mode)
        and (v_mode is not null or s.mode_effective <> 'backtest')
    ),
    filtered as (
      select t.*
      from public.trades t
      where t.user_id = v_uid
        and coalesce(lower(trim(t.mode)), '') <> 'backtest'
        and public.analytics_calendar_day(
          t.entry_time,
          t.exit_time,
          t.created_at
        ) = p_calendar_day
        and (
          p_account_id is null
          or nullif(trim(t.account_id), '') = p_account_id::text
        )
        and (
          v_mode is null
          or public.analytics_mode_effective(
            t.mode,
            t.account_type,
            t.trade_mode
          ) = v_mode
        )
    ),
    ordered as (
      select f.*
      from filtered f
      order by
        public.analytics_realized_sort_ts(
          f.entry_time,
          f.exit_time,
          f.created_at
        ) asc nulls last,
        f.id asc
    ),
    page as (
      select * from ordered limit 200
    ),
    trades_json as (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'user_id', r.user_id,
            'account_id', r.account_id,
            'ticker', r.ticker,
            'direction', r.direction,
            'pnl', r.pnl,
            'rr', r.rr,
            'contracts', r.contracts,
            'entry_time', r.entry_time,
            'exit_time', r.exit_time,
            'created_at', to_char(r.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'mode', r.mode,
            'account_type', r.account_type,
            'trade_mode', r.trade_mode,
            'session', r.session,
            'image_url', r.image_url,
            'image_display_mode', r.image_display_mode,
            'is_public', r.is_public,
            'account_name', r.account_name,
            'strategy', r.strategy,
            'duration_seconds', r.duration_seconds,
            'duration_text', r.duration_text,
            'public_description', r.public_description
          )
        ),
        '[]'::jsonb
      ) as trades
      from page r
    )
    select jsonb_build_object(
      'revision', (select revision from state),
      'state_updated_at', (select updated_at from state),
      'calendar_day', p_calendar_day,
      'account_id', p_account_id,
      'mode', v_mode,
      'aggregate', (select to_jsonb(aggregate) from aggregate),
      'trades', (select trades from trades_json)
    )
  );
end;
$$;

revoke all on function public.rpc_v1_analytics_calendar_day_trades(date, uuid, text) from public;
grant execute on function public.rpc_v1_analytics_calendar_day_trades(date, uuid, text) to authenticated;

comment on function public.rpc_v1_analytics_calendar_day_trades is
  'Calendar V2 day drill-down: TradeSummary rows for one analytics_calendar_day (ET civil, no 18:00 roll).';
