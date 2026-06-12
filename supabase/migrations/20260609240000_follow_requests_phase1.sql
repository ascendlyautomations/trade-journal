-- Phase 1: Private account follow requests (pending approval flow).
-- Prerequisite: followers RLS (20260609180000), notifications RLS (20260609210000).
--
-- Scope:
--   follow_requests table + RLS
--   Block direct followers INSERT to private profiles
--   follow_request notification insert policy (API + optional client)
--
-- Out of scope (later phases):
--   Content RLS, follower list hiding, approve/decline RPC, count denormalization

-- =============================================================================
-- 1. follow_requests
-- =============================================================================

create table if not exists public.follow_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users (id) on delete cascade,
  target_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint follow_requests_status_ck check (status in ('pending', 'declined')),
  constraint follow_requests_requester_target_unique unique (requester_id, target_id)
);

create index if not exists follow_requests_target_pending_idx
  on public.follow_requests (target_id, created_at desc)
  where status = 'pending';

create index if not exists follow_requests_requester_idx
  on public.follow_requests (requester_id, created_at desc);

comment on table public.follow_requests is
  'Pending follow requests for private profiles. Approved requests become followers rows (later phase).';

-- =============================================================================
-- 2. followers — block instant follow of private profiles
-- =============================================================================

drop policy if exists "followers_insert_own" on public.followers;

create policy "followers_insert_own"
  on public.followers
  for insert
  to authenticated
  with check (
    follower_id = auth.uid()
    and not exists (
      select 1
      from public.profiles p
      where p.id = following_id
        and coalesce(p.is_private, false) = true
    )
  );

comment on policy "followers_insert_own" on public.followers is
  'Users may follow public profiles immediately; private profiles require follow_requests (phase 1).';

-- =============================================================================
-- 3. follow_requests RLS
-- =============================================================================

alter table public.follow_requests enable row level security;

drop policy if exists "follow_requests_select_participant" on public.follow_requests;
drop policy if exists "follow_requests_insert_requester" on public.follow_requests;
drop policy if exists "follow_requests_delete_requester_pending" on public.follow_requests;

create policy "follow_requests_select_participant"
  on public.follow_requests
  for select
  to authenticated
  using (
    requester_id = auth.uid()
    or target_id = auth.uid()
  );

create policy "follow_requests_insert_requester"
  on public.follow_requests
  for insert
  to authenticated
  with check (
    requester_id = auth.uid()
    and requester_id <> target_id
    and status = 'pending'
    and exists (
      select 1
      from public.profiles p
      where p.id = target_id
        and coalesce(p.is_private, false) = true
    )
    and not exists (
      select 1
      from public.followers f
      where f.follower_id = auth.uid()
        and f.following_id = target_id
    )
  );

create policy "follow_requests_delete_requester_pending"
  on public.follow_requests
  for delete
  to authenticated
  using (
    requester_id = auth.uid()
    and status = 'pending'
  );

grant select, insert, delete on table public.follow_requests to authenticated;

-- =============================================================================
-- 4. notifications — follow_request type
-- =============================================================================

create policy "notifications_insert_follow_request"
  on public.notifications
  for insert
  to authenticated
  with check (
    type = 'follow_request'
    and sender_id = auth.uid()
    and user_id is not null
    and user_id <> auth.uid()
    and exists (
      select 1
      from public.follow_requests fr
      where fr.requester_id = auth.uid()
        and fr.target_id = notifications.user_id
        and fr.status = 'pending'
    )
  );

comment on policy "notifications_insert_follow_request" on public.notifications is
  'Follow-request notification only when a pending follow_requests row exists.';

-- =============================================================================
-- ROLLBACK (manual)
-- =============================================================================
-- drop policy if exists "notifications_insert_follow_request" on public.notifications;
--
-- drop policy if exists "follow_requests_delete_requester_pending" on public.follow_requests;
-- drop policy if exists "follow_requests_insert_requester" on public.follow_requests;
-- drop policy if exists "follow_requests_select_participant" on public.follow_requests;
--
-- drop policy if exists "followers_insert_own" on public.followers;
-- create policy "followers_insert_own"
--   on public.followers for insert to authenticated
--   with check (follower_id = auth.uid());
--
-- drop table if exists public.follow_requests;
