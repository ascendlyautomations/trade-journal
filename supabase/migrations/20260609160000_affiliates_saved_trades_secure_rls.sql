-- Phase 3: Secure RLS on public.affiliates and public.saved_trades only.
--
-- Prerequisite: none (no application changes required).
--
-- affiliates
--   SELECT — owner: user_id = auth.uid()
--          — admin: exists in admin_users
--   INSERT/UPDATE/DELETE — no client policies (deny authenticated/anon).
--          Service-role API routes, Stripe webhook, and security-definer RPCs
--          (e.g. admin_affiliate_application_approve) continue to write unchanged.
--
-- saved_trades
--   SELECT  — user_id = auth.uid()
--   INSERT  — user_id = auth.uid()
--   DELETE  — user_id = auth.uid()
--   UPDATE  — not used by app; no policy (denied)
--
-- Pre-flight (run in SQL editor before applying):
--   select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
--   from pg_policies
--   where schemaname = 'public'
--     and tablename in ('affiliates', 'saved_trades')
--   order by tablename, policyname;
--
-- Post-apply smoke (authenticated affiliate owner):
--   select id, code from public.affiliates where user_id = auth.uid();
-- Post-apply smoke (anon must return 0 rows / permission error):
--   -- curl with anon key against /rest/v1/affiliates?select=id&limit=1

-- =============================================================================
-- 1. affiliates
-- =============================================================================

alter table public.affiliates enable row level security;

-- Remove permissive / legacy / duplicate policies (safe if absent)
drop policy if exists "affiliates_select_own" on public.affiliates;
drop policy if exists "affiliates_select_admin" on public.affiliates;
drop policy if exists "Allow all affiliates" on public.affiliates;
drop policy if exists "Allow read affiliates" on public.affiliates;
drop policy if exists "Allow anyone to read affiliates" on public.affiliates;
drop policy if exists "TEMP allow all affiliates" on public.affiliates;
drop policy if exists "affiliates_select_all" on public.affiliates;
drop policy if exists "affiliates_insert_own" on public.affiliates;
drop policy if exists "affiliates_update_own" on public.affiliates;
drop policy if exists "affiliates_delete_own" on public.affiliates;
drop policy if exists "Users can read own affiliates" on public.affiliates;
drop policy if exists "Users can view own affiliates" on public.affiliates;

create policy "affiliates_select_own"
  on public.affiliates
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "affiliates_select_admin"
  on public.affiliates
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  );

revoke all on table public.affiliates from anon;
grant select on table public.affiliates to authenticated;

-- =============================================================================
-- 2. saved_trades
-- =============================================================================

alter table public.saved_trades enable row level security;

drop policy if exists "saved_trades_select_own" on public.saved_trades;
drop policy if exists "saved_trades_insert_own" on public.saved_trades;
drop policy if exists "saved_trades_delete_own" on public.saved_trades;
drop policy if exists "Allow all saved_trades" on public.saved_trades;
drop policy if exists "Allow read saved_trades" on public.saved_trades;
drop policy if exists "Allow anyone to read saved_trades" on public.saved_trades;
drop policy if exists "TEMP allow all saved_trades" on public.saved_trades;
drop policy if exists "saved_trades_select_all" on public.saved_trades;
drop policy if exists "Users can read own saved_trades" on public.saved_trades;
drop policy if exists "Users can insert own saved_trades" on public.saved_trades;
drop policy if exists "Users can delete own saved_trades" on public.saved_trades;

create policy "saved_trades_select_own"
  on public.saved_trades
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "saved_trades_insert_own"
  on public.saved_trades
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "saved_trades_delete_own"
  on public.saved_trades
  for delete
  to authenticated
  using (user_id = auth.uid());

revoke all on table public.saved_trades from anon;
grant select, insert, delete on table public.saved_trades to authenticated;

-- =============================================================================
-- ROLLBACK (manual — INSECURE, emergency only)
-- =============================================================================
-- scripts/rollback-20260609160000-affiliates-saved-trades-rls.sql
