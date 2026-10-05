-- Direct EXECUTE for anon survived the public revoke. Guests must not call the
-- owner journal list. Authenticated execute stays.

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
) from anon;
