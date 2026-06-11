-- ROLLBACK for supabase/migrations/20260609180000_followers_follows_secure_rls.sql
-- INSECURE — emergency only. Restores pre-hardening open access.
-- NOT a migration — run manually in SQL editor only.
-- Does NOT undo legacy follows → followers backfill.

-- =============================================================================
-- 1. followers — drop Phase 5 policies
-- =============================================================================
drop policy if exists "followers_select_public" on public.followers;
drop policy if exists "followers_insert_own" on public.followers;
drop policy if exists "followers_delete_own" on public.followers;

create policy "followers_select_all"
  on public.followers
  for select
  using (true);

grant select, insert, delete on table public.followers to anon, authenticated;

-- =============================================================================
-- 2. follows — restore client read access
-- =============================================================================
drop policy if exists "follows_select_public" on public.follows;
drop policy if exists "follows_insert_own" on public.follows;
drop policy if exists "follows_delete_own" on public.follows;

create policy "follows_select_all"
  on public.follows
  for select
  using (true);

grant select, insert, delete on table public.follows to anon, authenticated;

-- Optional full disable (only if RLS was off before Phase 5):
-- alter table public.followers disable row level security;
-- alter table public.follows disable row level security;
