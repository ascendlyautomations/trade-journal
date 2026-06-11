-- Phase 6: Secure RLS on public.profile_posts and public.stories only.
-- Prerequisite: followers RLS deployed (20260609180000).
--
-- Read visibility (matches profile access model):
--   - Post/story owner (user_id = auth.uid())
--   - Public profile (profiles.is_private is not true)
--   - Private profile: authenticated followers only
--
-- Writes: owner only (user_id = auth.uid()).
--
-- Pre-flight (run in SQL editor before applying):
--   select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
--   from pg_policies
--   where schemaname = 'public'
--     and tablename in ('profile_posts', 'stories')
--   order by tablename, policyname;

-- =============================================================================
-- 1. profile_posts
-- =============================================================================
alter table public.profile_posts enable row level security;

drop policy if exists "profile_posts_select_visible" on public.profile_posts;
drop policy if exists "profile_posts_insert_own" on public.profile_posts;
drop policy if exists "profile_posts_update_own" on public.profile_posts;
drop policy if exists "profile_posts_delete_own" on public.profile_posts;
drop policy if exists "profile_posts_select_all" on public.profile_posts;
drop policy if exists "Allow all profile_posts" on public.profile_posts;
drop policy if exists "Allow read profile_posts" on public.profile_posts;
drop policy if exists "Allow anyone to read profile_posts" on public.profile_posts;
drop policy if exists "TEMP allow all profile_posts" on public.profile_posts;

create policy "profile_posts_select_visible"
  on public.profile_posts
  for select
  to anon, authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.profiles p
      where p.id = profile_posts.user_id
        and coalesce(p.is_private, false) = false
    )
    or (
      auth.uid() is not null
      and exists (
        select 1
        from public.followers f
        where f.following_id = profile_posts.user_id
          and f.follower_id = auth.uid()
      )
    )
  );

create policy "profile_posts_insert_own"
  on public.profile_posts
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "profile_posts_update_own"
  on public.profile_posts
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "profile_posts_delete_own"
  on public.profile_posts
  for delete
  to authenticated
  using (user_id = auth.uid());

grant select on table public.profile_posts to anon, authenticated;
grant insert, update, delete on table public.profile_posts to authenticated;

-- =============================================================================
-- 2. stories
-- =============================================================================
alter table public.stories enable row level security;

drop policy if exists "stories_select_visible" on public.stories;
drop policy if exists "stories_insert_own" on public.stories;
drop policy if exists "stories_update_own" on public.stories;
drop policy if exists "stories_delete_own" on public.stories;
drop policy if exists "stories_select_all" on public.stories;
drop policy if exists "Allow all stories" on public.stories;
drop policy if exists "Allow read stories" on public.stories;
drop policy if exists "Allow anyone to read stories" on public.stories;
drop policy if exists "TEMP allow all stories" on public.stories;

create policy "stories_select_visible"
  on public.stories
  for select
  to anon, authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.profiles p
      where p.id = stories.user_id
        and coalesce(p.is_private, false) = false
    )
    or (
      auth.uid() is not null
      and exists (
        select 1
        from public.followers f
        where f.following_id = stories.user_id
          and f.follower_id = auth.uid()
      )
    )
  );

create policy "stories_insert_own"
  on public.stories
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "stories_update_own"
  on public.stories
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "stories_delete_own"
  on public.stories
  for delete
  to authenticated
  using (user_id = auth.uid());

grant select on table public.stories to anon, authenticated;
grant insert, update, delete on table public.stories to authenticated;

-- =============================================================================
-- ROLLBACK (manual — INSECURE, emergency only)
-- =============================================================================
-- scripts/rollback-20260609190000-profile-posts-stories-rls.sql
