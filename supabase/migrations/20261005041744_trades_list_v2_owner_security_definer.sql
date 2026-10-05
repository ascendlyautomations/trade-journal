-- rpc_v1_trades_list_bootstrap_v2 was recreated as SECURITY INVOKER by the
-- copy-trade journal migration. Authenticated no longer has table SELECT on
-- public.trades, so that invoker body fails with 42501 when it reads owner
-- journal columns (notes, account_id, source_account_id, psychology, …).
-- Restore the owner-only definer contract. The function still returns only
-- auth.uid() rows and does not accept a user id.

alter function public.rpc_v1_trades_list_bootstrap_v2(
  integer,
  text,
  text,
  text,
  text,
  timestamp with time zone,
  timestamp with time zone,
  text,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text
) security definer
set search_path = public, pg_temp;

comment on function public.rpc_v1_trades_list_bootstrap_v2(
  integer,
  text,
  text,
  text,
  text,
  timestamp with time zone,
  timestamp with time zone,
  text,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text
) is
  'Owner journal trades list. SECURITY DEFINER so private trade columns stay unreadable to other authenticated users. Rows are limited to auth.uid().';

revoke all on function public.rpc_v1_trades_list_bootstrap_v2(
  integer,
  text,
  text,
  text,
  text,
  timestamp with time zone,
  timestamp with time zone,
  text,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text
) from public;

grant execute on function public.rpc_v1_trades_list_bootstrap_v2(
  integer,
  text,
  text,
  text,
  text,
  timestamp with time zone,
  timestamp with time zone,
  text,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text
) to authenticated;
