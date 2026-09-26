-- Phase C2B: Dashboard V3 — one trade_daily_stats read per scope, five preset bundles.

create or replace function public.analytics_dashboard_metrics_multi_preset_bundles(
  p_user_id uuid,
  p_as_of date,
  p_account_id uuid default null
)
returns jsonb
language sql
stable
set search_path = public
as $$
  with preset_keys as (
    select unnest(array['d7', 'd30', 'd90', 'ytd', 'all']::text[]) as preset
  ),
  bounds as (
    select
      pk.preset,
      b.start_day,
      b.end_day
    from preset_keys pk
    cross join lateral public.analytics_dashboard_preset_bounds(p_as_of, pk.preset) b
  ),
  bounds_all as (
    select ba.start_day, ba.end_day
    from public.analytics_dashboard_preset_bounds(p_as_of, 'all') ba
  ),
  source as (
    select s.*
    from public.trade_daily_stats s
    cross join bounds_all ba
    where s.user_id = p_user_id
      and s.calendar_day between ba.start_day and ba.end_day
      and s.mode_effective is distinct from 'backtest'
      and (p_account_id is null or s.account_id is not distinct from p_account_id)
  ),
  agg as (
    select
      b.preset,
      b.start_day,
      b.end_day,
      public.analytics_dashboard_compose_metrics(
        coalesce(sum(s.trade_count), 0)::integer,
        coalesce(sum(s.win_count), 0)::integer,
        coalesce(sum(s.loss_count), 0)::integer,
        coalesce(sum(s.breakeven_count), 0)::integer,
        coalesce(sum(s.net_pnl), 0),
        coalesce(sum(s.gross_profit), 0),
        coalesce(sum(s.gross_loss), 0),
        coalesce(sum(s.long_count), 0)::integer,
        coalesce(sum(s.long_pnl), 0),
        coalesce(sum(s.short_count), 0)::integer,
        coalesce(sum(s.short_pnl), 0),
        coalesce(sum(s.sum_rr), 0),
        coalesce(sum(s.rr_count), 0)::integer,
        coalesce(sum(s.sum_hold_seconds), 0)::bigint,
        coalesce(sum(s.hold_count), 0)::integer,
        max(s.largest_win),
        min(s.largest_loss)
      ) as metrics
    from bounds b
    left join source s
      on s.calendar_day between b.start_day and b.end_day
    group by b.preset, b.start_day, b.end_day
  )
  select coalesce(
    jsonb_object_agg(
      a.preset,
      jsonb_build_object(
        'preset', a.preset,
        'start', a.start_day,
        'end', a.end_day,
        'metrics', a.metrics
      )
      order by array_position(array['d7', 'd30', 'd90', 'ytd', 'all']::text[], a.preset)
    ),
    '{}'::jsonb
  )
  from agg a;
$$;

comment on function public.analytics_dashboard_metrics_multi_preset_bundles(uuid, date, uuid) is
  'Dashboard V3 internal — five preset metric bundles from one trade_daily_stats scan per account scope.';

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
  v_all_presets jsonb;
  v_account_metrics jsonb := '[]'::jsonb;
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

  v_all_presets := public.analytics_dashboard_metrics_multi_preset_bundles(v_uid, v_as_of, null);

  for v_acct in
    select a.id
    from public.accounts a
    where a.user_id = v_uid
    order by a.created_at asc nulls last, a.id asc
  loop
    v_acct_presets := public.analytics_dashboard_metrics_multi_preset_bundles(v_uid, v_as_of, v_acct.id);
    v_account_metrics := v_account_metrics || jsonb_build_array(jsonb_build_object(
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
      'payload_kind', 'dashboard_analytics_v3_compact',
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
      'presets', v_all_presets,
      'account_preset_metrics', v_account_metrics
    )
  );
end;
$$;

comment on function public.rpc_v1_analytics_dashboard_bootstrap_v3() is
  'Compact Dashboard V3 bootstrap: 5 aggregate preset bundles + per-account metrics matrix (C2B single-pass trade_daily_stats per scope).';

revoke all on function public.rpc_v1_analytics_dashboard_bootstrap_v3() from public;
grant execute on function public.rpc_v1_analytics_dashboard_bootstrap_v3() to authenticated;
