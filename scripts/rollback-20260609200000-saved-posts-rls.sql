-- ROLLBACK for supabase/migrations/20260609200000_saved_posts_secure_rls.sql
-- INSECURE — emergency only. Restores pre-hardening open access.
-- NOT a migration — run manually in SQL editor only.

drop policy if exists "saved_posts_select_own" on public.saved_posts;
drop policy if exists "saved_posts_insert_own" on public.saved_posts;
drop policy if exists "saved_posts_delete_own" on public.saved_posts;

create policy "saved_posts_select_all"
  on public.saved_posts
  for select
  using (true);

grant select, insert, delete on table public.saved_posts to anon, authenticated;

-- Optional full disable (only if RLS was off before Phase 7):
-- alter table public.saved_posts disable row level security;
