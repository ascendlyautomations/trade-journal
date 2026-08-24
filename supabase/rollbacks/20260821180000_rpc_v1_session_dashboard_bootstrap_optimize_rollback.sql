-- Rollback for 20260821180000_rpc_v1_session_dashboard_bootstrap_optimize.sql
-- Re-applies the pre-Phase-A function bodies. Run manually if rollback is needed.

drop index if exists public.accounts_user_id_created_at_idx;

-- Restore Session RPC from 20260819180000_rpc_v1_session_bootstrap.sql
-- Restore Dashboard RPC from 20260820211500_rpc_v1_dashboard_bootstrap_account_id_boundary.sql
--
-- Fastest path: check out those two migration files and run their CREATE OR REPLACE
-- blocks against the target database, or:
--   supabase db reset   (local only — destructive)
