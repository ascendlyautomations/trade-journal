-- ROLLBACK for supabase/migrations/20260609160000_affiliates_saved_trades_secure_rls.sql
-- INSECURE — emergency only. Restores pre-hardening open access.
-- NOT a migration — run manually in SQL editor only.

-- =============================================================================
-- 1. affiliates — drop Phase 3 policies
-- =============================================================================

drop policy if exists "affiliates_select_own" on public.affiliates;
drop policy if exists "affiliates_select_admin" on public.affiliates;

-- =============================================================================
-- 2. saved_trades — drop Phase 3 policies
-- =============================================================================

drop policy if exists "saved_trades_select_own" on public.saved_trades;
drop policy if exists "saved_trades_insert_own" on public.saved_trades;
drop policy if exists "saved_trades_delete_own" on public.saved_trades;

-- =============================================================================
-- 3. Restore permissive access (pre-audit production behavior)
-- =============================================================================

create policy "affiliates_select_all"
  on public.affiliates
  for select
  using (true);

create policy "saved_trades_select_all"
  on public.saved_trades
  for select
  using (true);

grant select on table public.affiliates to anon, authenticated;
grant select, insert, delete on table public.saved_trades to anon, authenticated;

-- Optional full disable (only if RLS was off before Phase 3):
-- alter table public.affiliates disable row level security;
-- alter table public.saved_trades disable row level security;
