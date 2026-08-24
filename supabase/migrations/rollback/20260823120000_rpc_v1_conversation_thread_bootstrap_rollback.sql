-- Rollback Phase G conversation thread bootstrap RPC.

revoke all on function public.rpc_v1_conversation_thread_bootstrap(uuid, integer, text, boolean) from authenticated;
drop function if exists public.rpc_v1_conversation_thread_bootstrap(uuid, integer, text, boolean);

revoke all on function public.rpc_v1_conversation_thread_message_row(uuid) from authenticated;
drop function if exists public.rpc_v1_conversation_thread_message_row(uuid);
