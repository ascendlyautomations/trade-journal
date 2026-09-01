-- Rollback: restore denormalized-column inbox RPC (pre-canonical-messages repair).

revoke all on function public._v2_messaging_inbox_preview_text(
  boolean, boolean, text, text, text, uuid
) from public;
revoke all on function public._v2_messaging_inbox_preview_text(
  boolean, boolean, text, text, text, uuid
) from anon;
drop function if exists public._v2_messaging_inbox_preview_text(
  boolean, boolean, text, text, text, uuid
);

-- Re-apply prior rpc_v2_messaging_bootstrap body by re-running:
-- supabase/migrations/20260821014228_rpc_v2_messaging_bootstrap.sql
