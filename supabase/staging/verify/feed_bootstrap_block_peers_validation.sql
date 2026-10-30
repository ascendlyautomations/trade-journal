-- Staging-only validation for 20261027120000_feed_bootstrap_block_peers_once.sql
-- Run after forward apply on hxlcvffvyadlxcsqxxoy (never on fobudrkniacatvilbofw).
--
-- Usage:
--   psql "$TRADETRAXS_STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/staging/verify/feed_bootstrap_block_peers_validation.sql
--
-- Optional JWT simulation for RPC calls (substitute real auth user uuids from staging):
--   \set viewer_uuid '00000000-0000-0000-0000-000000000001'
--   \set blocked_author_uuid '00000000-0000-0000-0000-000000000002'

-- ---------------------------------------------------------------------------
-- 1) Post-migration function shape (fail if still on per-row blocks)
-- ---------------------------------------------------------------------------
select
  (length(def) - length(replace(def, 'users_have_active_block(v_uid,', '')))
    / nullif(length('users_have_active_block(v_uid,'), 0) as per_row_block_checks,
  (length(def) - length(replace(def, 'get_active_block_peer_ids()', '')))
    / nullif(length('get_active_block_peer_ids()'), 0) as get_block_peer_calls,
  position('v_block_peers uuid[]' in def) > 0 as has_v_block_peers,
  position('v_guest or not (p.user_id = any (v_block_peers))' in def) > 0 as cand_post_filter,
  position('v_guest or not (s.user_id = any (v_block_peers))' in def) > 0 as story_filter
from (
  select pg_get_functiondef(p.oid) as def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_feed_bootstrap'
    and pg_get_function_identity_arguments(p.oid) =
      'p_scope text, p_content_filter text, p_limit integer, p_cursor text'
) x;

-- Expected after migration: per_row_block_checks = 0, get_block_peer_calls = 1,
-- has_v_block_peers / cand_post_filter / story_filter = true.

-- ---------------------------------------------------------------------------
-- 2) Invoker + helper availability
-- ---------------------------------------------------------------------------
select p.proname, p.prosecdef
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('rpc_v1_feed_bootstrap', 'get_active_block_peer_ids');

-- Expected: rpc_v1_feed_bootstrap prosecdef = false; get_active_block_peer_ids = true.

-- ---------------------------------------------------------------------------
-- 3) Bidirectional block equivalence (definer helpers; run as superuser / postgres)
-- ---------------------------------------------------------------------------
-- Replace :viewer and :author with staging user ids that have an active user_blocks row.
-- select public.users_have_active_block(:'viewer'::uuid, :'author'::uuid) as fn_row;
-- begin;
-- set local role authenticated;
-- set local request.jwt.claim.sub = :'viewer';
-- select :'author'::uuid = any (public.get_active_block_peer_ids()) as array_membership;
-- rollback;

-- ---------------------------------------------------------------------------
-- 4) RPC smoke (authenticated viewer) — manual \set viewer_uuid first
-- ---------------------------------------------------------------------------
-- begin;
-- set local role authenticated;
-- set local request.jwt.claim.sub = :'viewer_uuid';
-- select jsonb_path_query_first(
--   public.rpc_v1_feed_bootstrap('following', 'all', 8, null),
--   '$.data.page_meta'
-- ) as following_first_page_meta;
-- select jsonb_path_query_first(
--   public.rpc_v1_feed_bootstrap('global', 'all', 8, null),
--   '$.data.page_meta'
-- ) as global_first_page_meta;
-- rollback;

-- Guest Explore (anon, no sub):
-- begin;
-- set local role anon;
-- select jsonb_path_query_first(
--   public.rpc_v1_feed_bootstrap('following', 'all', 8, null),
--   '$.data.scope'
-- ) as guest_scope_forced_global;
-- rollback;

-- ---------------------------------------------------------------------------
-- 5) EXPLAIN (no ANALYZE) — compare before/after migration on staging only
-- ---------------------------------------------------------------------------
-- begin;
-- set local role authenticated;
-- set local request.jwt.claim.sub = :'viewer_uuid';
-- explain (verbose, costs, buffers off)
-- select public.rpc_v1_feed_bootstrap('following', 'all', 8, null);
-- explain (verbose, costs, buffers off)
-- select public.rpc_v1_feed_bootstrap('global', 'all', 8, null);
-- rollback;
