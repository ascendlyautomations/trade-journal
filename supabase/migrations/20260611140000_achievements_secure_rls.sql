-- Secure RLS on public.achievements.
-- Prerequisite: achievements table exists (created outside this migration chain).
--
-- SELECT
--   Owner   — user_id = auth.uid() (all own rows, public + private)
--   Others  — is_public = true only
--   Admin   — exists in admin_users (full read for admin tooling)
--
-- INSERT / UPDATE / DELETE — owner only (user_id = auth.uid())
--
-- Admin activity RPCs (SECURITY DEFINER) continue to bypass RLS unchanged.
--
-- Pre-flight (run in SQL editor before applying):
--   select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
--   from pg_policies
--   where schemaname = 'public' and tablename = 'achievements'
--   order by policyname;

alter table public.achievements enable row level security;

-- =============================================================================
-- Drop permissive / legacy / duplicate policies
-- =============================================================================
drop policy if exists "achievements_select_own" on public.achievements;
drop policy if exists "achievements_select_public" on public.achievements;
drop policy if exists "achievements_select_admin" on public.achievements;
drop policy if exists "achievements_insert_own" on public.achievements;
drop policy if exists "achievements_update_own" on public.achievements;
drop policy if exists "achievements_delete_own" on public.achievements;
drop policy if exists "Allow all achievements" on public.achievements;
drop policy if exists "Allow read achievements" on public.achievements;
drop policy if exists "Allow anyone to read achievements" on public.achievements;
drop policy if exists "TEMP allow all achievements" on public.achievements;
drop policy if exists "achievements_select_all" on public.achievements;
drop policy if exists "Users can read achievements" on public.achievements;
drop policy if exists "Users can insert achievements" on public.achievements;
drop policy if exists "Users can update achievements" on public.achievements;
drop policy if exists "Users can delete achievements" on public.achievements;
drop policy if exists "Users can read own achievements" on public.achievements;
drop policy if exists "Users can insert own achievements" on public.achievements;
drop policy if exists "Users can update own achievements" on public.achievements;
drop policy if exists "Users can delete own achievements" on public.achievements;

-- =============================================================================
-- SELECT
-- =============================================================================
create policy "achievements_select_own"
  on public.achievements
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "achievements_select_public"
  on public.achievements
  for select
  to authenticated
  using (coalesce(is_public, false) = true);

create policy "achievements_select_admin"
  on public.achievements
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  );

-- =============================================================================
-- Writes — owner only
-- =============================================================================
create policy "achievements_insert_own"
  on public.achievements
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "achievements_update_own"
  on public.achievements
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "achievements_delete_own"
  on public.achievements
  for delete
  to authenticated
  using (user_id = auth.uid());

-- =============================================================================
-- Grants
-- =============================================================================
revoke all on table public.achievements from anon;
grant select, insert, update, delete on table public.achievements to authenticated;

-- =============================================================================
-- ROLLBACK (manual — INSECURE, emergency only)
-- =============================================================================
-- drop policy if exists "achievements_select_own" on public.achievements;
-- drop policy if exists "achievements_select_public" on public.achievements;
-- drop policy if exists "achievements_select_admin" on public.achievements;
-- drop policy if exists "achievements_insert_own" on public.achievements;
-- drop policy if exists "achievements_update_own" on public.achievements;
-- drop policy if exists "achievements_delete_own" on public.achievements;
