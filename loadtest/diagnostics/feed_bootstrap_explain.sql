-- Staging / local only — EXPLAIN (no ANALYZE) for rpc_v1_feed_bootstrap before/after
-- 20261027120000_feed_bootstrap_block_peers_once.sql
--
-- Compare: InitPlan / SubPlan count for users_have_active_block vs one get_active_block_peer_ids.

-- ---------------------------------------------------------------------------
-- Setup (substitute viewer uuid)
-- ---------------------------------------------------------------------------
-- begin;
-- set local role authenticated;
-- set local request.jwt.claim.sub = '<viewer-uuid>';

-- ---------------------------------------------------------------------------
-- First page — following (typical authenticated home)
-- ---------------------------------------------------------------------------
-- explain (verbose, costs, buffers off)
-- select public.rpc_v1_feed_bootstrap('following', 'all', 8, null);

-- ---------------------------------------------------------------------------
-- First page — global
-- ---------------------------------------------------------------------------
-- explain (verbose, costs, buffers off)
-- select public.rpc_v1_feed_bootstrap('global', 'all', 8, null);

-- ---------------------------------------------------------------------------
-- Cursor page — paste next_cursor from prior response
-- ---------------------------------------------------------------------------
-- explain (verbose, costs, buffers off)
-- select public.rpc_v1_feed_bootstrap(
--   'following',
--   'all',
--   8,
--   '<cursor-from-next_cursor>'
-- );

-- rollback;

-- ---------------------------------------------------------------------------
-- Block peer helper (should appear once in plan, not per cand row)
-- ---------------------------------------------------------------------------
-- explain (verbose, costs, buffers off)
-- select public.get_active_block_peer_ids();
