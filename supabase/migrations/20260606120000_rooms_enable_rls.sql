-- Phase 1: Trade Room security — RLS on public.rooms only.
-- Does not modify room_members, room_messages, room_presence, or room_sections.

-- Helper: active membership (safe while room_members RLS remains disabled).
create or replace function public.is_active_room_member(
  p_room_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
    from public.room_members m
    where m.room_id = p_room_id
      and m.user_id = p_user_id
      and m.left_at is null
  );
$$;

comment on function public.is_active_room_member(uuid, uuid) is
  'True when p_user_id is an active (non-left) member of p_room_id.';

alter table public.rooms enable row level security;

-- SELECT: active members (sidebar via loadMemberRooms)
drop policy if exists "rooms_select_member" on public.rooms;
create policy "rooms_select_member"
  on public.rooms
  for select
  to authenticated
  using (
    public.is_active_room_member(id, auth.uid())
  );

-- SELECT: room owner (owner check, pre-create lookup, own room always visible)
drop policy if exists "rooms_select_owner" on public.rooms;
create policy "rooms_select_owner"
  on public.rooms
  for select
  to authenticated
  using (
    owner_user_id = auth.uid()
  );

-- SELECT: profile room visibility (View Trade Room on public profiles)
drop policy if exists "rooms_select_profile_public" on public.rooms;
create policy "rooms_select_profile_public"
  on public.rooms
  for select
  to anon, authenticated
  using (
    owner_user_id is not null
  );

-- SELECT: invite room lookup (slug for owned rooms; name fallback for legacy)
drop policy if exists "rooms_select_invite" on public.rooms;
create policy "rooms_select_invite"
  on public.rooms
  for select
  to authenticated
  using (
    slug is not null
    or owner_user_id is null
  );

-- INSERT: personal Trade Room creation (one owned room per user)
drop policy if exists "rooms_insert_own" on public.rooms;
create policy "rooms_insert_own"
  on public.rooms
  for insert
  to authenticated
  with check (
    owner_user_id = auth.uid()
    and not exists (
      select 1
      from public.rooms r
      where r.owner_user_id = auth.uid()
    )
  );

-- UPDATE: owner only (name, show_on_profile, image_url)
drop policy if exists "rooms_update_owner" on public.rooms;
create policy "rooms_update_owner"
  on public.rooms
  for update
  to authenticated
  using (
    owner_user_id = auth.uid()
  )
  with check (
    owner_user_id = auth.uid()
  );

-- DELETE: owner only (not used in app today; reserved for future)
drop policy if exists "rooms_delete_owner" on public.rooms;
create policy "rooms_delete_owner"
  on public.rooms
  for delete
  to authenticated
  using (
    owner_user_id = auth.uid()
  );

-- =============================================================================
-- ROLLBACK (run manually to revert this migration)
-- =============================================================================
-- drop policy if exists "rooms_select_member" on public.rooms;
-- drop policy if exists "rooms_select_owner" on public.rooms;
-- drop policy if exists "rooms_select_profile_public" on public.rooms;
-- drop policy if exists "rooms_select_invite" on public.rooms;
-- drop policy if exists "rooms_insert_own" on public.rooms;
-- drop policy if exists "rooms_update_owner" on public.rooms;
-- drop policy if exists "rooms_delete_owner" on public.rooms;
--
-- alter table public.rooms disable row level security;
--
-- drop function if exists public.is_active_room_member(uuid, uuid);
