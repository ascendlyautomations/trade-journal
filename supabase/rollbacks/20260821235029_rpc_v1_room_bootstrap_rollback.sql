-- Rollback: rpc_v1_room_bootstrap (Phase F)
-- Apply manually on staging/production if rollback is required.

revoke all on function public.rpc_v1_room_bootstrap(uuid, uuid, integer, boolean) from authenticated;
revoke all on function public.rpc_v1_room_bootstrap_message_row(uuid) from authenticated;

drop function if exists public.rpc_v1_room_bootstrap(uuid, uuid, integer, boolean);
drop function if exists public.rpc_v1_room_bootstrap_message_row(uuid);
