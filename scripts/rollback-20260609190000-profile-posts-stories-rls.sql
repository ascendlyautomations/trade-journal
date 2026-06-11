-- ROLLBACK for supabase/migrations/20260609190000_profile_posts_stories_secure_rls.sql
-- INSECURE — emergency only. Restores pre-hardening open access.
-- NOT a migration — run manually in SQL editor only.

-- =============================================================================
-- 1. profile_posts
-- =============================================================================
drop policy if exists "profile_posts_select_visible" on public.profile_posts;
drop policy if exists "profile_posts_insert_own" on public.profile_posts;
drop policy if exists "profile_posts_update_own" on public.profile_posts;
drop policy if exists "profile_posts_delete_own" on public.profile_posts;

create policy "profile_posts_select_all"
  on public.profile_posts
  for select
  using (true);

grant select, insert, update, delete on table public.profile_posts to anon, authenticated;

-- =============================================================================
-- 2. stories
-- =============================================================================
drop policy if exists "stories_select_visible" on public.stories;
drop policy if exists "stories_insert_own" on public.stories;
drop policy if exists "stories_update_own" on public.stories;
drop policy if exists "stories_delete_own" on public.stories;

create policy "stories_select_all"
  on public.stories
  for select
  using (true);

grant select, insert, update, delete on table public.stories to anon, authenticated;

-- Optional full disable (only if RLS was off before Phase 6):
-- alter table public.profile_posts disable row level security;
-- alter table public.stories disable row level security;
