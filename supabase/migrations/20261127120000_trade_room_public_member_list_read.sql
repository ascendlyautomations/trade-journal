-- Trade Room member directory: authenticated users may read active memberships in
-- public (non-private) rooms without joining. Private rooms unchanged (member / owner / moderator paths only).

-- =============================================================================
-- Helper: authoritative public-room check (does not grant room SELECT beyond RLS)
-- =============================================================================

create or replace function public.is_public_trade_room(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.rooms r
    where r.id = p_room_id
      and coalesce(r.is_private, false) = false
  );
$$;

comment on function public.is_public_trade_room(uuid) is
  'True when the room exists and is not private. Used for read-only member directory on public Trade Rooms.';

revoke all on function public.is_public_trade_room(uuid) from public;
grant execute on function public.is_public_trade_room(uuid) to authenticated;

-- =============================================================================
-- room_members: read-only directory for public rooms
-- =============================================================================

drop policy if exists "room_members_select_public_directory" on public.room_members;
create policy "room_members_select_public_directory"
  on public.room_members
  for select
  to authenticated
  using (
    left_at is null
    and public.is_public_trade_room(room_id)
  );

comment on policy "room_members_select_public_directory" on public.room_members is
  'Authenticated users may list active members in public Trade Rooms without membership. No write access.';

-- =============================================================================
-- Moderator / cosmetic badges on the member list (read-only; public rooms only)
-- =============================================================================

drop policy if exists "room_member_tags_select_member" on public.room_member_tags;
create policy "room_member_tags_select_member"
  on public.room_member_tags
  for select
  to authenticated
  using (
    public.is_active_room_member(room_id, auth.uid())
    or public.is_room_owner(room_id, auth.uid())
    or public.is_public_trade_room(room_id)
  );

drop policy if exists "room_member_tag_assignments_select_member" on public.room_member_tag_assignments;
create policy "room_member_tag_assignments_select_member"
  on public.room_member_tag_assignments
  for select
  to authenticated
  using (
    public.is_active_room_member(room_id, auth.uid())
    or public.is_room_owner(room_id, auth.uid())
    or public.is_public_trade_room(room_id)
  );