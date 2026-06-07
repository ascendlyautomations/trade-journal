-- Phase 3B: Trade Room security — RLS on public.room_members only.
-- Depends on Phase 1: public.is_active_room_member(uuid, uuid)
-- Depends on Phase 2: public.is_room_owner(uuid, uuid)
-- Does not modify rooms, room_messages, room_presence, or room_sections.
--
-- Prerequisites (production):
--   - public.room_members.left_at (nullable timestamptz) for soft leave / rejoin
--   - Application leave flow sets left_at; rejoin sets left_at = null
--
-- Deploy atomically: all policies must exist before ENABLE ROW LEVEL SECURITY.
-- is_active_room_member() is security invoker; it reads the caller's own row,
-- which requires room_members_select_self below.

-- =============================================================================
-- Future hooks (stubs until room_bans / invite-only join ship)
-- =============================================================================

create or replace function public.is_room_banned(
  p_room_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select false;
$$;

comment on function public.is_room_banned(uuid, uuid) is
  'Placeholder: returns false until public.room_bans exists. Gate room_members INSERT/join when implemented.';

comment on function public.is_active_room_member(uuid, uuid) is
  'True when p_user_id is an active (non-left) member of p_room_id. Invoker reads room_members; requires self-select RLS policy.';

-- =============================================================================
-- UPDATE guard: only left_at may change (soft leave, rejoin, owner kick)
-- =============================================================================

create or replace function public.room_members_before_update_guard()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.room_id is distinct from new.room_id
     or old.user_id is distinct from new.user_id
  then
    raise exception 'room_id and user_id are immutable on room_members';
  end if;

  return new;
end;
$$;

drop trigger if exists room_members_before_update_guard on public.room_members;

create trigger room_members_before_update_guard
  before update on public.room_members
  for each row
  execute function public.room_members_before_update_guard();

-- =============================================================================
-- RLS policies
-- =============================================================================

alter table public.room_members enable row level security;

-- SELECT: own memberships (sidebar, join/rejoin lookup, is_active_room_member self-check)
drop policy if exists "room_members_select_self" on public.room_members;
create policy "room_members_select_self"
  on public.room_members
  for select
  to authenticated
  using (
    user_id = auth.uid()
  );

-- SELECT: room owner member list and stats (loadMemberStats active/left counts)
drop policy if exists "room_members_select_owner" on public.room_members;
create policy "room_members_select_owner"
  on public.room_members
  for select
  to authenticated
  using (
    public.is_room_owner(room_id, auth.uid())
  );

-- INSERT: self-join and createUserRoom owner row; room must exist; ban hooks
drop policy if exists "room_members_insert_self" on public.room_members;
create policy "room_members_insert_self"
  on public.room_members
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and left_at is null
    and exists (
      select 1
      from public.rooms r
      where r.id = room_id
    )
    and not public.is_room_banned(room_id, auth.uid())
    and not exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and coalesce(p.is_banned, false)
    )
  );

-- UPDATE: soft leave (left_at = now) and rejoin (left_at = null)
drop policy if exists "room_members_update_self" on public.room_members;
create policy "room_members_update_self"
  on public.room_members
  for update
  to authenticated
  using (
    user_id = auth.uid()
  )
  with check (
    user_id = auth.uid()
  );

-- UPDATE: owner kick via soft leave (future moderation UI)
drop policy if exists "room_members_update_owner" on public.room_members;
create policy "room_members_update_owner"
  on public.room_members
  for update
  to authenticated
  using (
    public.is_room_owner(room_id, auth.uid())
    and user_id <> auth.uid()
  )
  with check (
    public.is_room_owner(room_id, auth.uid())
    and user_id <> auth.uid()
  );

-- DELETE: self (legacy hard-leave cleanup; app uses soft leave)
drop policy if exists "room_members_delete_self" on public.room_members;
create policy "room_members_delete_self"
  on public.room_members
  for delete
  to authenticated
  using (
    user_id = auth.uid()
  );

-- DELETE: owner hard-remove member (future kick; prefer update_owner soft kick)
drop policy if exists "room_members_delete_owner" on public.room_members;
create policy "room_members_delete_owner"
  on public.room_members
  for delete
  to authenticated
  using (
    public.is_room_owner(room_id, auth.uid())
    and user_id <> auth.uid()
  );

-- =============================================================================
-- ROLLBACK (run manually to revert this migration)
-- =============================================================================
-- drop policy if exists "room_members_select_self" on public.room_members;
-- drop policy if exists "room_members_select_owner" on public.room_members;
-- drop policy if exists "room_members_insert_self" on public.room_members;
-- drop policy if exists "room_members_update_self" on public.room_members;
-- drop policy if exists "room_members_update_owner" on public.room_members;
-- drop policy if exists "room_members_delete_self" on public.room_members;
-- drop policy if exists "room_members_delete_owner" on public.room_members;
--
-- drop trigger if exists room_members_before_update_guard on public.room_members;
-- drop function if exists public.room_members_before_update_guard();
--
-- alter table public.room_members disable row level security;
--
-- drop function if exists public.is_room_banned(uuid, uuid);
--
-- comment on function public.is_active_room_member(uuid, uuid) is
--   'True when p_user_id is an active (non-left) member of p_room_id.';

-- =============================================================================
-- DEPLOYMENT CHECKLIST
-- =============================================================================
-- [ ] Phase 1 applied (rooms RLS + is_active_room_member)
-- [ ] Phase 2 applied (room_messages RLS + is_room_owner)
-- [ ] Phase 3A applied in app (leave uses UPDATE left_at, not DELETE)
-- [ ] public.room_members.left_at column exists in target database
-- [ ] Apply this migration in a single transaction (policies then ENABLE RLS)
-- [ ] Verify createUserRoom: owner INSERT membership on new room
-- [ ] Verify joinRoom: INSERT first join; UPDATE left_at = null on rejoin
-- [ ] Verify handleLeaveRoom: UPDATE left_at; sidebar refreshes without room
-- [ ] Verify loadMemberRooms: only left_at IS NULL rows in sidebar
-- [ ] Verify owner loadMemberStats: active + left counts for owned room
-- [ ] Verify invite flow: slug lookup then join INSERT
-- [ ] Verify Phase 1 rooms SELECT still works for active members
-- [ ] Verify Phase 2 messages read/post for active members
-- [ ] Verify banned platform user (profiles.is_banned) cannot INSERT membership
-- [ ] Verify cross-user INSERT/UPDATE/DELETE denied via PostgREST
-- [ ] Verify anon has no access to room_members

-- =============================================================================
-- EDGE CASES
-- =============================================================================
-- 1. is_active_room_member + RLS: function is security invoker. Policies on
--    rooms/messages call it with p_user_id = auth.uid(). Self-select policy
--    must allow reading the caller's row (including left_at IS NOT NULL rows
--    for rejoin lookup). Do not enable RLS without policies.
--
-- 2. Rejoin after soft leave: existing row with left_at set → UPDATE only
--    (INSERT blocked by unique constraint on room_id + user_id). Self UPDATE
--    policy and trigger allow left_at = null.
--
-- 3. Duplicate active join: INSERT fails with 23505; app treats as already
--    joined. INSERT policy requires left_at IS NULL on new rows only.
--
-- 4. INSERT room-exists check uses invoker access on rooms. Joiners rely on
--    rooms_select_invite (Phase 1); createUserRoom owner relies on
--    rooms_select_owner. User who cannot read a room cannot verify existence
--    under RLS and INSERT fails — intentional for hidden rooms.
--
-- 5. Owner membership: owner is inserted at room creation. Owner cannot use
--    leave UI; self UPDATE/DELETE policies still apply if attempted. Owner
--    cannot delete/update own row via owner moderation policies (user_id <>).
--
-- 6. Platform ban: INSERT denied when profiles.is_banned = true. Does not
--    auto-remove existing memberships; revoke separately if needed.
--
-- 7. is_room_banned stub: always false until room_bans table replaces body.
--    Future: check room_bans where room_id and user_id match and not expired.
--
-- 8. Hard DELETE vs soft leave: app uses soft leave (Phase 3A). Self DELETE
--    policy retained for cleanup and legacy rows. Owner DELETE for hard kick.
--
-- 9. Schema drift: production may use surrogate id + created_at; repo migration
--    uses composite PK + joined_at. RLS is row-based; guard trigger only
--    protects room_id and user_id immutability.
--
-- 10. Service role / admin: bypasses RLS. Application uses anon/authenticated
--     keys only for Trade Rooms UI.
