-- Owner-only daily check-in window for psychology analytics bootstrap.
-- Returns check-ins whose Eastern trade dates appear in the user's scoped trades.

create or replace function public.rpc_v1_psychology_check_in_window(
  p_account_id uuid default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_check_ins jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  with scoped_trades as (
    select t.*
    from public.trades t
    where t.user_id = v_uid
      and (p_account_id is null or t.account_id = p_account_id::text)
  ),
  trade_dates as (
    select distinct coalesce(
      nullif(trim(st.trade_date), '')::date,
      nullif(trim(st.date), '')::date
    ) as d
    from scoped_trades st
    where coalesce(nullif(trim(st.trade_date), ''), nullif(trim(st.date), '')) is not null
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', ci.id,
        'user_id', ci.user_id,
        'check_in_date', ci.check_in_date,
        'sleep_hours', ci.sleep_hours,
        'sleep_quality', ci.sleep_quality,
        'morning_rating', ci.morning_rating,
        'stress_level', ci.stress_level,
        'energy_level', ci.energy_level,
        'focus_level', ci.focus_level,
        'notes', ci.notes,
        'created_at', to_char(ci.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'updated_at', to_char(ci.updated_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      )
      order by ci.check_in_date desc
    ),
    '[]'::jsonb
  )
  into v_check_ins
  from public.trader_daily_check_ins ci
  where ci.user_id = v_uid
    and ci.check_in_date in (select d from trade_dates where d is not null);

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'check_ins', coalesce(v_check_ins, '[]'::jsonb)
    )
  );
end;
$$;

comment on function public.rpc_v1_psychology_check_in_window(uuid) is
  'Owner-only daily check-ins aligned to trade dates in scope — for native psychology analytics bootstrap.';

revoke all on function public.rpc_v1_psychology_check_in_window(uuid) from public;
grant execute on function public.rpc_v1_psychology_check_in_window(uuid) to authenticated;
