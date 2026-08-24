-- Rollback Phase H1 prop firm bootstrap RPC.

revoke all on function public.rpc_v1_prop_firm_bootstrap() from authenticated;
revoke all on function public.rpc_v1_prop_firm_bootstrap() from public;
drop function if exists public.rpc_v1_prop_firm_bootstrap();
