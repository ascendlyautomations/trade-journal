-- Dashboard V3 payload fix: remove (1 + N accounts) × 5 duplicated full preset bundles.
-- Bootstrap ships aggregate presets (5) + per-account metrics-only matrix.
-- Per-account charts (equity/distributions/insights) load via rpc_v1_analytics_dashboard_account_charts_v3.

create or replace function public.analytics_dashboard_metrics_preset_bundle(
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
    'metrics', public.analytics_dashboard_metrics_from_daily(p_user_id, v_start, v_end, p_account_id)
  );
end;
$$;

create or replace function public.analytics_dashboard_charts_bundle(
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
  v_all_presets jsonb := '{}'::jsonb;
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

  foreach v_preset in array v_presets loop
    v_all_presets := v_all_presets || jsonb_build_object(
      v_preset,
      public.analytics_dashboard_preset_bundle(v_uid, v_preset, v_as_of, null)
    );
  end loop;

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
        public.analytics_dashboard_metrics_preset_bundle(v_uid, v_preset, v_as_of, v_acct.id)
      );
    end loop;
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

create or replace function public.rpc_v1_analytics_dashboard_account_charts_v3(
  p_account_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_as_of date;
  v_presets text[] := array['d7', 'd30', 'd90', 'ytd', 'all'];
  v_preset text;
  v_charts jsonb := '{}'::jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_account_id is null then
    raise exception 'invalid_account' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.accounts a
    where a.user_id = v_uid and a.id = p_account_id
  ) then
    raise exception 'account_not_found' using errcode = '22023';
  end if;

  v_as_of := public.analytics_dashboard_as_of_et();

  foreach v_preset in array v_presets loop
    v_charts := v_charts || jsonb_build_object(
      v_preset,
      public.analytics_dashboard_charts_bundle(v_uid, v_preset, v_as_of, p_account_id)
    );
  end loop;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'account_id', p_account_id,
      'as_of_et', v_as_of,
      'presets', v_charts
    )
  );
end;
$$;

comment on function public.rpc_v1_analytics_dashboard_bootstrap_v3() is
  'Compact Dashboard V3 bootstrap: 5 aggregate preset bundles + per-account metrics matrix (no duplicated charts).';

comment on function public.rpc_v1_analytics_dashboard_account_charts_v3(uuid) is
  'Dashboard V3 per-account charts for all presets (equity, distributions, insights).';

revoke all on function public.rpc_v1_analytics_dashboard_account_charts_v3(uuid) from public;
grant execute on function public.rpc_v1_analytics_dashboard_account_charts_v3(uuid) to authenticated;
