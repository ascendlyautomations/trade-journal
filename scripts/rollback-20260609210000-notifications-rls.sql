-- ROLLBACK for supabase/migrations/20260609210000_notifications_secure_rls.sql
-- INSECURE — emergency only. Restores pre-hardening open access.
-- NOT a migration — run manually in SQL editor only.

drop policy if exists "notifications_select_own" on public.notifications;
drop policy if exists "notifications_update_own" on public.notifications;
drop policy if exists "notifications_delete_own" on public.notifications;
drop policy if exists "notifications_insert_like" on public.notifications;
drop policy if exists "notifications_insert_comment" on public.notifications;
drop policy if exists "notifications_insert_message" on public.notifications;
drop policy if exists "notifications_insert_follow" on public.notifications;

-- Restore permissive read (pre-Phase-8 dashboard pattern).
create policy "notifications_select_all"
  on public.notifications
  for select
  using (true);

grant select, insert, update, delete on table public.notifications to anon, authenticated;

-- Optional full disable (only if RLS was off before Phase 8):
-- alter table public.notifications disable row level security;
