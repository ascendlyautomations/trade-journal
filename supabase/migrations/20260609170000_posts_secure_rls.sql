-- Phase 4: Secure RLS on public.posts only.
-- Prerequisite: trades RLS deployed (20260609120000); feed/profile/DM read paths unchanged.
--
-- Target:
--   SELECT  — all rows (feed is public content; presence in posts = published trade post)
--           — anon + authenticated
--   INSERT  — user_id = auth.uid()
--   UPDATE  — user_id = auth.uid()
--   DELETE  — user_id = auth.uid()
--
-- Pre-flight (run in SQL editor before applying):
--   select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
--   from pg_policies
--   where schemaname = 'public' and tablename = 'posts'
--   order by policyname;

-- =============================================================================
-- 1. Enable RLS (idempotent)
-- =============================================================================
alter table public.posts enable row level security;

-- =============================================================================
-- 2. Remove permissive / legacy / duplicate policies
-- =============================================================================
drop policy if exists "posts_select_public" on public.posts;
drop policy if exists "posts_insert_own" on public.posts;
drop policy if exists "posts_update_own" on public.posts;
drop policy if exists "posts_delete_own" on public.posts;
drop policy if exists "Allow all posts" on public.posts;
drop policy if exists "Allow read posts" on public.posts;
drop policy if exists "Allow anyone to read posts" on public.posts;
drop policy if exists "TEMP allow all posts" on public.posts;
drop policy if exists "Users can read posts" on public.posts;
drop policy if exists "Users can insert posts" on public.posts;
drop policy if exists "Users can update posts" on public.posts;
drop policy if exists "Users can delete posts" on public.posts;
drop policy if exists "Users can insert own posts" on public.posts;
drop policy if exists "Users can update own posts" on public.posts;
drop policy if exists "Users can delete own posts" on public.posts;

-- =============================================================================
-- 3. SELECT — public feed (all post rows are published feed content)
-- =============================================================================
create policy "posts_select_public"
  on public.posts
  for select
  to anon, authenticated
  using (true);

-- =============================================================================
-- 4. Writes — owner only
-- =============================================================================
create policy "posts_insert_own"
  on public.posts
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "posts_update_own"
  on public.posts
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "posts_delete_own"
  on public.posts
  for delete
  to authenticated
  using (user_id = auth.uid());

-- =============================================================================
-- 5. Grants (RLS filters; anon read-only)
-- =============================================================================
grant select on table public.posts to anon, authenticated;
grant insert, update, delete on table public.posts to authenticated;

-- =============================================================================
-- ROLLBACK (manual — INSECURE, emergency only)
-- =============================================================================
-- scripts/rollback-20260609170000-posts-rls.sql
