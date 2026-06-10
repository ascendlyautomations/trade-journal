-- Phase 2: Secure RLS on public.trades only.
-- Prerequisite: Phase 1 application changes deployed (public-only explore/leaderboard,
-- owner/public trade detail guards, profile analytics split, public-only DM/room sharing).
--
-- Target:
--   SELECT  — owner: user_id = auth.uid()
--           — public: is_public = true (any user including anon)
--   INSERT  — user_id = auth.uid()
--   UPDATE  — user_id = auth.uid()
--   DELETE  — user_id = auth.uid()
--
-- Do NOT leave any permissive SELECT policy with USING (true); PostgreSQL ORs permissive
-- policies and a single true policy defeats owner/public restrictions.

-- =============================================================================
-- 1. Enable RLS (idempotent)
-- =============================================================================
alter table public.trades enable row level security;

-- =============================================================================
-- 2. Remove dangerous / duplicate / legacy policies
-- =============================================================================

-- Production permissive SELECT (USING true) — MUST remove all three
drop policy if exists "TEMP allow all trades" on public.trades;
drop policy if exists "Allow anyone to read trades" on public.trades;
drop policy if exists "Allow users to view shared trades" on public.trades;

-- Duplicate owner SELECT — consolidate into trades_select_own
drop policy if exists "Users can see their own trades" on public.trades;
drop policy if exists "Users can view own trades" on public.trades;

-- Prior canonical names from earlier hardening attempts (safe if absent)
drop policy if exists "trades_select_own" on public.trades;
drop policy if exists "trades_select_public" on public.trades;
drop policy if exists "trades_insert_own" on public.trades;
drop policy if exists "trades_update_own" on public.trades;
drop policy if exists "trades_delete_own" on public.trades;

-- Common dashboard starter / legacy names (safe if absent)
drop policy if exists "Users can insert their own trades" on public.trades;
drop policy if exists "Users can update their own trades" on public.trades;
drop policy if exists "Users can delete their own trades" on public.trades;
drop policy if exists "Users can insert own trades" on public.trades;
drop policy if exists "Users can update own trades" on public.trades;
drop policy if exists "Users can delete own trades" on public.trades;
drop policy if exists "Allow insert trades" on public.trades;
drop policy if exists "Allow update trades" on public.trades;
drop policy if exists "Allow delete trades" on public.trades;
drop policy if exists "Allow read trades" on public.trades;

-- =============================================================================
-- 3. Canonical SELECT policies
-- =============================================================================

-- Owner: full read access to own journal (private + public + backtest + imported)
create policy "trades_select_own"
  on public.trades
  for select
  to authenticated
  using (user_id = auth.uid());

-- Public: any viewer may read rows explicitly marked public (feed, explore, trade links)
create policy "trades_select_public"
  on public.trades
  for select
  to anon, authenticated
  using (is_public = true);

-- =============================================================================
-- 4. Canonical write policies (owner only)
-- =============================================================================

create policy "trades_insert_own"
  on public.trades
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "trades_update_own"
  on public.trades
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "trades_delete_own"
  on public.trades
  for delete
  to authenticated
  using (user_id = auth.uid());

-- =============================================================================
-- 5. Grants (idempotent; ensures PostgREST roles can attempt operations; RLS filters)
-- =============================================================================
grant select, insert, update, delete on table public.trades to authenticated;
grant select on table public.trades to anon;

-- =============================================================================
-- ROLLBACK (manual — restores openness; INSECURE, emergency only)
-- =============================================================================
-- drop policy if exists "trades_select_own" on public.trades;
-- drop policy if exists "trades_select_public" on public.trades;
-- drop policy if exists "trades_insert_own" on public.trades;
-- drop policy if exists "trades_update_own" on public.trades;
-- drop policy if exists "trades_delete_own" on public.trades;
-- create policy "Allow anyone to read trades" on public.trades for select using (true);
