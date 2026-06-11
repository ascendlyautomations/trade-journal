-- Phase 7: Secure RLS on public.saved_posts only.
-- Prerequisite: none (no application changes required).
-- Mirrors saved_trades model (20260609160000).
--
-- Target:
--   SELECT  — user_id = auth.uid()
--   INSERT  — user_id = auth.uid()
--   DELETE  — user_id = auth.uid()
--   UPDATE  — not used by app; no policy (denied)
--
-- Pre-flight (run in SQL editor before applying):
--   select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
--   from pg_policies
--   where schemaname = 'public' and tablename = 'saved_posts'
--   order by policyname;

alter table public.saved_posts enable row level security;

drop policy if exists "saved_posts_select_own" on public.saved_posts;
drop policy if exists "saved_posts_insert_own" on public.saved_posts;
drop policy if exists "saved_posts_delete_own" on public.saved_posts;
drop policy if exists "Allow all saved_posts" on public.saved_posts;
drop policy if exists "Allow read saved_posts" on public.saved_posts;
drop policy if exists "Allow anyone to read saved_posts" on public.saved_posts;
drop policy if exists "TEMP allow all saved_posts" on public.saved_posts;
drop policy if exists "saved_posts_select_all" on public.saved_posts;
drop policy if exists "Users can read own saved_posts" on public.saved_posts;
drop policy if exists "Users can insert own saved_posts" on public.saved_posts;
drop policy if exists "Users can delete own saved_posts" on public.saved_posts;

create policy "saved_posts_select_own"
  on public.saved_posts
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "saved_posts_insert_own"
  on public.saved_posts
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "saved_posts_delete_own"
  on public.saved_posts
  for delete
  to authenticated
  using (user_id = auth.uid());

revoke all on table public.saved_posts from anon;
grant select, insert, delete on table public.saved_posts to authenticated;

-- =============================================================================
-- ROLLBACK (manual — INSECURE, emergency only)
-- =============================================================================
-- scripts/rollback-20260609200000-saved-posts-rls.sql
