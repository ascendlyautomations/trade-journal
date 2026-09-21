-- Phase 1C — extend shadow compare to all composable / additive metrics.

create or replace function public.analytics_numeric_near(
  p_a numeric,
  p_b numeric,
  p_abs_tol numeric default 0.0001
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select abs(coalesce(p_a, 0) - coalesce(p_b, 0)) <= p_abs_tol;
$$;

create or replace function public.analytics_raw_normal_range_metrics(
  p_user_id uuid,
  p_start date,
  p_end date,
  p_account_id uuid default null,
  p_mode text default null
)
returns jsonb
language sql
stable
set search_path = public
as $$
  with v_mode as (
    select nullif(lower(trim(coalesce(p_mode, ''))), '') as mode_filter
  ),
  raw_normal as (
    select t.*
    from public.trades t
    cross join lateral public.analytics_trade_bucket_key(t) b
    cross join v_mode vf
    where t.user_id = p_user_id
      and b.calendar_day between p_start and p_end
      and (p_account_id is null or b.account_id is not distinct from p_account_id)
      and (vf.mode_filter is null or b.mode_effective = vf.mode_filter)
      and (vf.mode_filter is not null or b.mode_effective <> 'backtest')
  )
  select jsonb_build_object(
    'trade_count', count(*)::integer,
    'win_count', count(*) filter (where coalesce(pnl, 0) > 0)::integer,
    'loss_count', count(*) filter (where coalesce(pnl, 0) < 0)::integer,
    'breakeven_count', count(*) filter (where coalesce(pnl, 0) = 0)::integer,
    'net_pnl', coalesce(sum(pnl), 0),
    'gross_profit', coalesce(sum(pnl) filter (where coalesce(pnl, 0) > 0), 0),
    'gross_loss', coalesce(sum(pnl) filter (where coalesce(pnl, 0) < 0), 0),
    'long_count', count(*) filter (where lower(trim(coalesce(direction, ''))) = 'long')::integer,
    'long_pnl', coalesce(sum(pnl) filter (where lower(trim(coalesce(direction, ''))) = 'long'), 0),
    'short_count', count(*) filter (
      where lower(trim(coalesce(direction, ''))) <> 'long'
        and nullif(trim(coalesce(direction, '')), '') is not null
    )::integer,
    'short_pnl', coalesce(sum(pnl) filter (
      where lower(trim(coalesce(direction, ''))) <> 'long'
        and nullif(trim(coalesce(direction, '')), '') is not null
    ), 0),
    'sum_rr', coalesce(sum(rr) filter (where rr is not null), 0),
    'rr_count', count(*) filter (where rr is not null)::integer,
    'sum_hold_seconds', coalesce(sum(public.analytics_trade_hold_seconds(t)) filter (
      where public.analytics_trade_hold_seconds(t) is not null
    ), 0)::bigint,
    'hold_count', count(*) filter (where public.analytics_trade_hold_seconds(t) is not null)::integer,
    'largest_win', max(pnl) filter (where coalesce(pnl, 0) > 0),
    'largest_loss', min(pnl) filter (where coalesce(pnl, 0) < 0)
  )
  from raw_normal t;
$$;

create or replace function public.rpc_v1_analytics_shadow_compare_range(
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
  v_raw jsonb;
  v_agg jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  v_raw := public.analytics_raw_normal_range_metrics(
    v_uid, p_start, p_end, p_account_id, p_mode
  );

  select jsonb_build_object(
    'trade_count', coalesce(sum(trade_count), 0)::integer,
    'win_count', coalesce(sum(win_count), 0)::integer,
    'loss_count', coalesce(sum(loss_count), 0)::integer,
    'breakeven_count', coalesce(sum(breakeven_count), 0)::integer,
    'net_pnl', coalesce(sum(net_pnl), 0),
    'gross_profit', coalesce(sum(gross_profit), 0),
    'gross_loss', coalesce(sum(gross_loss), 0),
    'long_count', coalesce(sum(long_count), 0)::integer,
    'long_pnl', coalesce(sum(long_pnl), 0),
    'short_count', coalesce(sum(short_count), 0)::integer,
    'short_pnl', coalesce(sum(short_pnl), 0),
    'sum_rr', coalesce(sum(sum_rr), 0),
    'rr_count', coalesce(sum(rr_count), 0)::integer,
    'sum_hold_seconds', coalesce(sum(sum_hold_seconds), 0)::bigint,
    'hold_count', coalesce(sum(hold_count), 0)::integer,
    'largest_win', max(largest_win),
    'largest_loss', min(largest_loss)
  )
  into v_agg
  from public.trade_daily_stats s
  where s.user_id = v_uid
    and s.calendar_day between p_start and p_end
    and (p_account_id is null or s.account_id is not distinct from p_account_id)
    and (v_mode is null or s.mode_effective = v_mode)
    and (v_mode is not null or s.mode_effective <> 'backtest');

  return (
    with m_raw_legacy as (
      select
        count(*)::integer as trade_count,
        coalesce(sum(pnl), 0) as net_pnl
      from public.trades t
      where t.user_id = v_uid
        and public.analytics_legacy_trading_day_key(
          t.entry_time, t.exit_time, t.created_at
        ) between p_start and p_end
        and (p_account_id is null or public.analytics_trade_account_uuid(t.account_id) is not distinct from p_account_id)
        and (v_mode is null or public.analytics_mode_effective(
          (select a.mode from public.accounts a where a.id::text = nullif(trim(t.account_id), '') and a.user_id = t.user_id limit 1),
          t.account_type,
          coalesce(t.trade_mode, t.mode)
        ) = v_mode)
        and (v_mode is not null or public.analytics_mode_effective(
          (select a.mode from public.accounts a where a.id::text = nullif(trim(t.account_id), '') and a.user_id = t.user_id limit 1),
          t.account_type,
          coalesce(t.trade_mode, t.mode)
        ) <> 'backtest')
    ),
    derived as (
      select
        v_agg as agg,
        v_raw as raw,
        case when coalesce((v_agg->>'trade_count')::int, 0) = 0 then null
          else (v_agg->>'win_count')::numeric / (v_agg->>'trade_count')::numeric end as agg_win_rate,
        case when coalesce((v_raw->>'trade_count')::int, 0) = 0 then null
          else (v_raw->>'win_count')::numeric / (v_raw->>'trade_count')::numeric end as raw_win_rate,
        case when coalesce((v_agg->>'gross_loss')::numeric, 0) = 0 then null
          else (v_agg->>'gross_profit')::numeric / abs((v_agg->>'gross_loss')::numeric) end as agg_profit_factor,
        case when coalesce((v_raw->>'gross_loss')::numeric, 0) = 0 then null
          else (v_raw->>'gross_profit')::numeric / abs((v_raw->>'gross_loss')::numeric) end as raw_profit_factor
    )
    select jsonb_build_object(
      'start', p_start,
      'end', p_end,
      'account_id', p_account_id,
      'mode', v_mode,
      'date_semantics_note',
        'normal_calendar_day = analytics_calendar_day (no 18:00 ET). legacy_trading_day = analytics_legacy_trading_day_key. Differences vs legacy Calendar are EXPECTED_LEGACY_DATE_SEMANTICS, not math corruption.',
      'aggregate', v_agg,
      'raw_normal_calendar', v_raw,
      'raw_legacy_trading_day_summary', (select to_jsonb(m_raw_legacy) from m_raw_legacy),
      'expected_legacy_day_mismatch', (
        select (v_raw->>'trade_count')::int is distinct from trade_count
          or public.analytics_numeric_near((v_raw->>'net_pnl')::numeric, net_pnl) is false
        from m_raw_legacy
      ),
      'parity_aggregate_vs_raw_normal', jsonb_build_object(
        'trade_count', (v_agg->>'trade_count')::int = (v_raw->>'trade_count')::int,
        'win_count', (v_agg->>'win_count')::int = (v_raw->>'win_count')::int,
        'loss_count', (v_agg->>'loss_count')::int = (v_raw->>'loss_count')::int,
        'breakeven_count', (v_agg->>'breakeven_count')::int = (v_raw->>'breakeven_count')::int,
        'net_pnl', public.analytics_numeric_near((v_agg->>'net_pnl')::numeric, (v_raw->>'net_pnl')::numeric),
        'gross_profit', public.analytics_numeric_near((v_agg->>'gross_profit')::numeric, (v_raw->>'gross_profit')::numeric),
        'gross_loss', public.analytics_numeric_near((v_agg->>'gross_loss')::numeric, (v_raw->>'gross_loss')::numeric),
        'long_count', (v_agg->>'long_count')::int = (v_raw->>'long_count')::int,
        'long_pnl', public.analytics_numeric_near((v_agg->>'long_pnl')::numeric, (v_raw->>'long_pnl')::numeric),
        'short_count', (v_agg->>'short_count')::int = (v_raw->>'short_count')::int,
        'short_pnl', public.analytics_numeric_near((v_agg->>'short_pnl')::numeric, (v_raw->>'short_pnl')::numeric),
        'sum_rr', public.analytics_numeric_near((v_agg->>'sum_rr')::numeric, (v_raw->>'sum_rr')::numeric),
        'rr_count', (v_agg->>'rr_count')::int = (v_raw->>'rr_count')::int,
        'sum_hold_seconds', (v_agg->>'sum_hold_seconds')::bigint = (v_raw->>'sum_hold_seconds')::bigint,
        'hold_count', (v_agg->>'hold_count')::int = (v_raw->>'hold_count')::int,
        'largest_win', public.analytics_numeric_near((v_agg->>'largest_win')::numeric, (v_raw->>'largest_win')::numeric, 0.0001)
          or ((v_agg->>'largest_win') is null and (v_raw->>'largest_win') is null),
        'largest_loss', public.analytics_numeric_near((v_agg->>'largest_loss')::numeric, (v_raw->>'largest_loss')::numeric, 0.0001)
          or ((v_agg->>'largest_loss') is null and (v_raw->>'largest_loss') is null),
        'win_rate', public.analytics_numeric_near(
          (select agg_win_rate from derived),
          (select raw_win_rate from derived),
          0.000001
        ) or ((select agg_win_rate from derived) is null and (select raw_win_rate from derived) is null),
        'profit_factor', public.analytics_numeric_near(
          (select agg_profit_factor from derived),
          (select raw_profit_factor from derived),
          0.000001
        ) or ((select agg_profit_factor from derived) is null and (select raw_profit_factor from derived) is null),
        'average_winner', public.analytics_numeric_near(
          case when (v_agg->>'win_count')::int = 0 then null
            else (v_agg->>'gross_profit')::numeric / (v_agg->>'win_count')::numeric end,
          case when (v_raw->>'win_count')::int = 0 then null
            else (v_raw->>'gross_profit')::numeric / (v_raw->>'win_count')::numeric end,
          0.0001
        ) or (
          (v_agg->>'win_count')::int = 0 and (v_raw->>'win_count')::int = 0
        ),
        'average_loser', public.analytics_numeric_near(
          case when (v_agg->>'loss_count')::int = 0 then null
            else abs((v_agg->>'gross_loss')::numeric) / (v_agg->>'loss_count')::numeric end,
          case when (v_raw->>'loss_count')::int = 0 then null
            else abs((v_raw->>'gross_loss')::numeric) / (v_raw->>'loss_count')::numeric end,
          0.0001
        ) or (
          (v_agg->>'loss_count')::int = 0 and (v_raw->>'loss_count')::int = 0
        ),
        'average_rr', public.analytics_numeric_near(
          case when (v_agg->>'rr_count')::int = 0 then null
            else (v_agg->>'sum_rr')::numeric / (v_agg->>'rr_count')::numeric end,
          case when (v_raw->>'rr_count')::int = 0 then null
            else (v_raw->>'sum_rr')::numeric / (v_raw->>'rr_count')::numeric end,
          0.000001
        ) or (
          (v_agg->>'rr_count')::int = 0 and (v_raw->>'rr_count')::int = 0
        ),
        'average_hold_seconds', public.analytics_numeric_near(
          case when (v_agg->>'hold_count')::int = 0 then null
            else (v_agg->>'sum_hold_seconds')::numeric / (v_agg->>'hold_count')::numeric end,
          case when (v_raw->>'hold_count')::int = 0 then null
            else (v_raw->>'sum_hold_seconds')::numeric / (v_raw->>'hold_count')::numeric end,
          0.01
        ) or (
          (v_agg->>'hold_count')::int = 0 and (v_raw->>'hold_count')::int = 0
        ),
        'profit_per_trade', public.analytics_numeric_near(
          case when (v_agg->>'trade_count')::int = 0 then null
            else (v_agg->>'net_pnl')::numeric / (v_agg->>'trade_count')::numeric end,
          case when (v_raw->>'trade_count')::int = 0 then null
            else (v_raw->>'net_pnl')::numeric / (v_raw->>'trade_count')::numeric end,
          0.0001
        ) or (
          (v_agg->>'trade_count')::int = 0 and (v_raw->>'trade_count')::int = 0
        )
      ),
      'parity_all_additive', (
        (v_agg->>'trade_count')::int = (v_raw->>'trade_count')::int
        and (v_agg->>'win_count')::int = (v_raw->>'win_count')::int
        and (v_agg->>'loss_count')::int = (v_raw->>'loss_count')::int
        and (v_agg->>'breakeven_count')::int = (v_raw->>'breakeven_count')::int
        and public.analytics_numeric_near((v_agg->>'net_pnl')::numeric, (v_raw->>'net_pnl')::numeric)
        and public.analytics_numeric_near((v_agg->>'gross_profit')::numeric, (v_raw->>'gross_profit')::numeric)
        and public.analytics_numeric_near((v_agg->>'gross_loss')::numeric, (v_raw->>'gross_loss')::numeric)
        and (v_agg->>'long_count')::int = (v_raw->>'long_count')::int
        and public.analytics_numeric_near((v_agg->>'long_pnl')::numeric, (v_raw->>'long_pnl')::numeric)
        and (v_agg->>'short_count')::int = (v_raw->>'short_count')::int
        and public.analytics_numeric_near((v_agg->>'short_pnl')::numeric, (v_raw->>'short_pnl')::numeric)
        and public.analytics_numeric_near((v_agg->>'sum_rr')::numeric, (v_raw->>'sum_rr')::numeric)
        and (v_agg->>'rr_count')::int = (v_raw->>'rr_count')::int
        and (v_agg->>'sum_hold_seconds')::bigint = (v_raw->>'sum_hold_seconds')::bigint
        and (v_agg->>'hold_count')::int = (v_raw->>'hold_count')::int
        and (
          public.analytics_numeric_near((v_agg->>'largest_win')::numeric, (v_raw->>'largest_win')::numeric, 0.0001)
          or ((v_agg->>'largest_win') is null and (v_raw->>'largest_win') is null)
        )
        and (
          public.analytics_numeric_near((v_agg->>'largest_loss')::numeric, (v_raw->>'largest_loss')::numeric, 0.0001)
          or ((v_agg->>'largest_loss') is null and (v_raw->>'largest_loss') is null)
        )
      )
    )
  );
end;
$$;

revoke all on function public.analytics_raw_normal_range_metrics(uuid, date, date, uuid, text) from public;
grant execute on function public.analytics_raw_normal_range_metrics(uuid, date, date, uuid, text) to service_role;

revoke all on function public.rpc_v1_analytics_shadow_compare_range(date, date, uuid, text) from public;
grant execute on function public.rpc_v1_analytics_shadow_compare_range(date, date, uuid, text) to authenticated;
