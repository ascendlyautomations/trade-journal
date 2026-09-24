-- Calendar V2: exclude backtest grains when mode is unset (matches CalendarAnalyticsAggregator).
-- Keeps trade_daily_stats-only read path; no raw-trades scan.

create or replace function public.rpc_v1_analytics_daily_range_bootstrap(
  p_start date,
  p_end date,
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
  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'invalid_date_range' using errcode = '22023';
  end if;

  return (
    with state as (
      select coalesce(u.revision, 0) as revision, u.updated_at
      from public.user_analytics_state u
      where u.user_id = v_uid
    ),
    rows as (
      select
        s.calendar_day,
        s.account_id,
        s.mode_effective,
        s.trade_count,
        s.win_count,
        s.loss_count,
        s.breakeven_count,
        s.net_pnl,
        s.gross_profit,
        s.gross_loss,
        s.long_count,
        s.long_pnl,
        s.short_count,
        s.short_pnl,
        s.sum_rr,
        s.rr_count,
        s.sum_hold_seconds,
        s.hold_count,
        s.largest_win,
        s.largest_loss,
        s.updated_at
      from public.trade_daily_stats s
      where s.user_id = v_uid
        and s.calendar_day between p_start and p_end
        and (p_account_id is null or s.account_id is not distinct from p_account_id)
        and (v_mode is not null or s.mode_effective <> 'backtest')
        and (v_mode is null or s.mode_effective = v_mode)
      order by s.calendar_day, s.mode_effective, s.account_id nulls first
    ),
    summary as (
      select
        coalesce(sum(r.trade_count), 0)::integer as trade_count,
        coalesce(sum(r.win_count), 0)::integer as win_count,
        coalesce(sum(r.loss_count), 0)::integer as loss_count,
        coalesce(sum(r.breakeven_count), 0)::integer as breakeven_count,
        coalesce(sum(r.net_pnl), 0) as net_pnl,
        coalesce(sum(r.gross_profit), 0) as gross_profit,
        coalesce(sum(r.gross_loss), 0) as gross_loss,
        coalesce(sum(r.long_count), 0)::integer as long_count,
        coalesce(sum(r.long_pnl), 0) as long_pnl,
        coalesce(sum(r.short_count), 0)::integer as short_count,
        coalesce(sum(r.short_pnl), 0) as short_pnl,
        coalesce(sum(r.sum_rr), 0) as sum_rr,
        coalesce(sum(r.rr_count), 0)::integer as rr_count,
        coalesce(sum(r.sum_hold_seconds), 0)::bigint as sum_hold_seconds,
        coalesce(sum(r.hold_count), 0)::integer as hold_count,
        max(r.largest_win) as largest_win,
        min(r.largest_loss) as largest_loss
      from rows r
    )
    select jsonb_build_object(
      'revision', (select revision from state),
      'state_updated_at', (select updated_at from state),
      'start', p_start,
      'end', p_end,
      'account_id', p_account_id,
      'mode', v_mode,
      'days', coalesce((select jsonb_agg(to_jsonb(r)) from rows r), '[]'::jsonb),
      'summary', (select to_jsonb(summary) from summary)
    )
  );
end;
$$;
