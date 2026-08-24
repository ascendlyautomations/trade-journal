-- Rollback: remove Getting Started signals RPC only.

drop function if exists public.rpc_v1_getting_started_signals();
