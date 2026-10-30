-- Run after apply-forward-migrations.sh
\set ON_ERROR_STOP on

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'trades' and column_name = 'realized_rr'
  ) then
    raise exception 'Missing trades.realized_rr (20261026160000)';
  end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'rpc_v1_ban_trade_room_member'
  ) then
    raise exception 'Missing rpc_v1_ban_trade_room_member (20261026170000)';
  end if;
end $$;

select 'schema_verification_forward passed' as result;
