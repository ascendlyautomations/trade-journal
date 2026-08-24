-- Phase C hardening rollback: remove V2 Messaging RPC only. V1 is untouched.

drop function if exists public.rpc_v2_messaging_bootstrap(integer, text, boolean);
drop function if exists public._v2_messaging_before_cursor(
  timestamptz, uuid, timestamptz, uuid, boolean
);
drop function if exists public._v2_messaging_parse_cursor(text);

drop index if exists public.notifications_user_id_message_unread_idx;
