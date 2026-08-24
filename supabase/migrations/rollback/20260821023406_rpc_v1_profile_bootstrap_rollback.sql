-- Rollback: drop Profile bootstrap RPC only.

drop function if exists public.rpc_v1_profile_bootstrap(text, text, integer, text);
