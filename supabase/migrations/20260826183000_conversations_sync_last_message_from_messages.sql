-- SUPERSEDED — do not deploy this trigger-based approach.
--
-- The inbox now reads canonical latest messages directly in:
--   20260826210000_rpc_v2_messaging_bootstrap_canonical_messages.sql
--
-- Rationale: trigger-only denormalization cannot handle DELETE, per-user hide,
-- or edit semantics completely; the inbox RPC must derive from public.messages.
--
-- This migration is intentionally a no-op placeholder so local migration history
-- remains linear for environments that already picked up the file name.

select 1;
