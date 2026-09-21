-- Fix rpc_v1_trades_list_bootstrap wire serialization: trades.entry_time / exit_time are text.
-- Without timestamptz cast, PostgreSQL resolves `text AT TIME ZONE 'utc'` as timezone('utc', text) → 42883.

create or replace function public.analytics_wire_trade_timestamp_utc(p_raw text)
returns text
language sql
stable
set search_path = public
as $$
  select case
    when public.analytics_parse_trade_timestamp(p_raw) is null then null
    else to_char(
      public.analytics_parse_trade_timestamp(p_raw) at time zone 'utc',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    )
  end;
$$;

do $patch$
declare
  v_def text;
  v_old_entry constant text :=
    '''entry_time'', to_char(r.entry_time at time zone ''utc'', ''YYYY-MM-DD"T"HH24:MI:SS.MS"Z"''),';
  v_new_entry constant text :=
    '''entry_time'', public.analytics_wire_trade_timestamp_utc(r.entry_time),';
  v_old_exit constant text :=
    '''exit_time'', to_char(r.exit_time at time zone ''utc'', ''YYYY-MM-DD"T"HH24:MI:SS.MS"Z"''),';
  v_new_exit constant text :=
    '''exit_time'', public.analytics_wire_trade_timestamp_utc(r.exit_time),';
begin
  foreach v_def in array array[
    pg_get_functiondef((
      select p.oid
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'rpc_v1_trades_list_bootstrap'
        and p.pronargs = 16
    )),
    pg_get_functiondef((
      select p.oid
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'rpc_v1_trades_list_bootstrap'
        and p.pronargs = 12
    ))
  ] loop
    if v_def is null then
      raise exception 'rpc_v1_trades_list_bootstrap overload missing';
    end if;
    if position(v_old_entry in v_def) = 0 or position(v_old_exit in v_def) = 0 then
      raise exception 'rpc_v1_trades_list_bootstrap body missing expected entry_time/exit_time wire format';
    end if;
    v_def := replace(replace(v_def, v_old_entry, v_new_entry), v_old_exit, v_new_exit);
    execute v_def;
  end loop;
end;
$patch$;
