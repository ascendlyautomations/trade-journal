-- rpc_v1_check_in_history_bootstrap can read trades again as SECURITY DEFINER.
-- trade_date and date are date columns, so trim() raised 42883 once the
-- 42501 permission error no longer stopped the query. Cast to text first.

do $mig$
declare
  src text;
  updated text;
begin
  select pg_get_functiondef(p.oid)
  into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_check_in_history_bootstrap'
    and pg_get_function_identity_arguments(p.oid) = 'p_start_date date, p_end_date date, p_account_id uuid';

  if src is null then
    raise exception 'rpc_v1_check_in_history_bootstrap was not found';
  end if;

  updated := replace(src, 'trim(t.trade_date)', 'trim(t.trade_date::text)');
  updated := replace(updated, 'trim(t.date)', 'trim(t.date::text)');

  if updated = src then
    raise exception 'check-in history date trim sites were not found';
  end if;

  execute updated;
end
$mig$;
