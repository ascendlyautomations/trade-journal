-- ROLLBACK for supabase/migrations/20260609170000_posts_secure_rls.sql
-- INSECURE — emergency only. Restores pre-hardening open access.
-- NOT a migration — run manually in SQL editor only.

drop policy if exists "posts_select_public" on public.posts;
drop policy if exists "posts_insert_own" on public.posts;
drop policy if exists "posts_update_own" on public.posts;
drop policy if exists "posts_delete_own" on public.posts;

-- Pre-Phase-4 behavior: unrestricted read; writes unguarded by RLS
create policy "posts_select_all"
  on public.posts
  for select
  using (true);

grant select, insert, update, delete on table public.posts to anon, authenticated;

-- Optional full disable (only if RLS was off before Phase 4):
-- alter table public.posts disable row level security;
