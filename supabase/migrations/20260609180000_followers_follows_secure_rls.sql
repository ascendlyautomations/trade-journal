-- Phase 5: Secure RLS on public.followers and lock down legacy public.follows.
-- Prerequisite: none (no application changes required).
--
-- followers (active social graph)
--   SELECT  — public (follower/following counts, modals, following feed discovery)
--   INSERT  — follower_id = auth.uid()
--   DELETE  — follower_id = auth.uid()
--   UPDATE  — not used by app; no policy (denied)
--
-- follows (legacy — zero app queries; 2 rows in production at audit)
--   Merge any unique edges into followers, then deny all client API access.
--
-- Pre-flight (run in SQL editor before applying):
--   select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
--   from pg_policies
--   where schemaname = 'public'
--     and tablename in ('followers', 'follows')
--   order by tablename, policyname;

-- =============================================================================
-- 1. Legacy follows → followers (idempotent; preserves orphan edges)
-- =============================================================================
insert into public.followers (follower_id, following_id, created_at)
select f.follower_id, f.following_id, now()
from public.follows f
where f.follower_id is not null
  and f.following_id is not null
  and not exists (
    select 1
    from public.followers fr
    where fr.follower_id = f.follower_id
      and fr.following_id = f.following_id
  );

-- =============================================================================
-- 2. followers
-- =============================================================================
alter table public.followers enable row level security;

drop policy if exists "followers_select_public" on public.followers;
drop policy if exists "followers_insert_own" on public.followers;
drop policy if exists "followers_delete_own" on public.followers;
drop policy if exists "Allow all followers" on public.followers;
drop policy if exists "Allow read followers" on public.followers;
drop policy if exists "Allow anyone to read followers" on public.followers;
drop policy if exists "TEMP allow all followers" on public.followers;
drop policy if exists "followers_select_all" on public.followers;
drop policy if exists "Users can read followers" on public.followers;
drop policy if exists "Users can insert followers" on public.followers;
drop policy if exists "Users can delete followers" on public.followers;
drop policy if exists "Users can insert own followers" on public.followers;
drop policy if exists "Users can delete own followers" on public.followers;

create policy "followers_select_public"
  on public.followers
  for select
  to anon, authenticated
  using (true);

create policy "followers_insert_own"
  on public.followers
  for insert
  to authenticated
  with check (follower_id = auth.uid());

create policy "followers_delete_own"
  on public.followers
  for delete
  to authenticated
  using (follower_id = auth.uid());

grant select on table public.followers to anon, authenticated;
grant insert, delete on table public.followers to authenticated;

-- =============================================================================
-- 3. follows — client lockdown (deprecated table)
-- =============================================================================
alter table public.follows enable row level security;

drop policy if exists "follows_select_public" on public.follows;
drop policy if exists "follows_insert_own" on public.follows;
drop policy if exists "follows_delete_own" on public.follows;
drop policy if exists "Allow all follows" on public.follows;
drop policy if exists "Allow read follows" on public.follows;
drop policy if exists "Allow anyone to read follows" on public.follows;
drop policy if exists "TEMP allow all follows" on public.follows;
drop policy if exists "follows_select_all" on public.follows;

revoke all on table public.follows from anon;
revoke all on table public.follows from authenticated;

-- =============================================================================
-- ROLLBACK (manual — INSECURE, emergency only)
-- =============================================================================
-- scripts/rollback-20260609180000-followers-follows-rls.sql
