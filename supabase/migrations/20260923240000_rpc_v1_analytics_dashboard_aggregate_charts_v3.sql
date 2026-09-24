-- All-accounts Dashboard V3 charts (equity/distributions/insights) on demand.
-- Compact bootstrap keeps metrics-only aggregate presets; charts load via this RPC.

create or replace function public.rpc_v1_analytics_dashboard_aggregate_charts_v3()
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

  v_as_of := public.analytics_dashboard_as_of_et();

  foreach v_preset in array v_presets loop
    v_charts := v_charts || jsonb_build_object(
      v_preset,
      public.analytics_dashboard_charts_bundle(v_uid, v_preset, v_as_of, null)
    );
  end loop;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'account_id', null,
      'as_of_et', v_as_of,
      'presets', v_charts
    )
  );
end;
$$;

comment on function public.rpc_v1_analytics_dashboard_aggregate_charts_v3() is
  'Dashboard V3 all-accounts charts for all presets (equity, distributions, insights).';

revoke all on function public.rpc_v1_analytics_dashboard_aggregate_charts_v3() from public;
grant execute on function public.rpc_v1_analytics_dashboard_aggregate_charts_v3() to authenticated;
