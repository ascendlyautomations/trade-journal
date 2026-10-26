-- Trade Room moderators: members assigned the preset "Moderator" tag may moderate
-- members and messages, but cannot change room settings, channels, or ownership.

-- =============================================================================
-- 1. Helpers
-- =============================================================================

create or replace function public.has_room_moderator_tag(p_room_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
    from public.room_member_tag_assignments a
    join public.room_member_tags t
      on t.id = a.tag_id
     and t.room_id = a.room_id
    where a.room_id = p_room_id
      and a.user_id = p_user_id
      and lower(trim(t.name)) = 'moderator'
  );
$$;

comment on function public.has_room_moderator_tag(uuid, uuid) is
  'True when the user has the preset Moderator member tag in the room.';

revoke all on function public.has_room_moderator_tag(uuid, uuid) from public;
grant execute on function public.has_room_moderator_tag(uuid, uuid) to authenticated;

create or replace function public.has_elevated_room_member_tag(p_room_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
    from public.room_member_tag_assignments a
    join public.room_member_tags t
      on t.id = a.tag_id
     and t.room_id = a.room_id
    where a.room_id = p_room_id
      and a.user_id = p_user_id
      and lower(trim(t.name)) in ('moderator', 'admin')
  );
$$;

comment on function public.has_elevated_room_member_tag(uuid, uuid) is
  'Moderator or Admin preset tag — only room owners may moderate these members (unless actor is owner).';

revoke all on function public.has_elevated_room_member_tag(uuid, uuid) from public;
grant execute on function public.has_elevated_room_member_tag(uuid, uuid) to authenticated;

create or replace function public.can_moderate_trade_room(p_room_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select
    public.can_manage_trade_room(p_room_id, p_user_id)
    or (
      public.is_active_room_member(p_room_id, p_user_id)
      and public.has_room_moderator_tag(p_room_id, p_user_id)
    );
$$;

comment on function public.can_moderate_trade_room(uuid, uuid) is
  'Room owner, platform admin on official rooms, or active member with Moderator tag.';

revoke all on function public.can_moderate_trade_room(uuid, uuid) from public;
grant execute on function public.can_moderate_trade_room(uuid, uuid) to authenticated;

create or replace function public.is_elevated_room_member_tag(p_tag_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
    from public.room_member_tags t
    where t.id = p_tag_id
      and lower(trim(t.name)) in ('moderator', 'admin')
  );
$$;

revoke all on function public.is_elevated_room_member_tag(uuid) from public;
grant execute on function public.is_elevated_room_member_tag(uuid) to authenticated;

create or replace function public.can_assign_room_member_tag(
  p_room_id uuid,
  p_user_id uuid,
  p_tag_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select
    public.can_moderate_trade_room(p_room_id, p_user_id)
    and (
      public.can_manage_trade_room(p_room_id, p_user_id)
      or not public.is_elevated_room_member_tag(p_tag_id)
    );
$$;

revoke all on function public.can_assign_room_member_tag(uuid, uuid, uuid) from public;
grant execute on function public.can_assign_room_member_tag(uuid, uuid, uuid) to authenticated;

create or replace function public.can_moderate_room_member_target(
  p_room_id uuid,
  p_actor uuid,
  p_target uuid
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select
    p_actor is not null
    and p_target is not null
    and p_target <> p_actor
    and not public.is_room_owner(p_room_id, p_target)
    and public.can_moderate_trade_room(p_room_id, p_actor)
    and (
      public.can_manage_trade_room(p_room_id, p_actor)
      or not public.has_elevated_room_member_tag(p_room_id, p_target)
    );
$$;

comment on function public.can_moderate_room_member_target(uuid, uuid, uuid) is
  'Moderators may act on regular members; owners may act on anyone except themselves.';

revoke all on function public.can_moderate_room_member_target(uuid, uuid, uuid) from public;
grant execute on function public.can_moderate_room_member_target(uuid, uuid, uuid) to authenticated;

-- =============================================================================
-- 2. room_messages — delete (moderators; not owner-authored messages unless actor is owner)
-- =============================================================================

drop policy if exists "room_messages_delete_owner" on public.room_messages;
create policy "room_messages_delete_moderator"
  on public.room_messages
  for delete
  to authenticated
  using (
    public.can_moderate_trade_room(room_id, auth.uid())
    and (
      public.can_manage_trade_room(room_id, auth.uid())
      or not public.is_room_owner(room_id, user_id)
    )
  );

-- =============================================================================
-- 3. room_members — remove (soft leave via update / hard delete)
-- =============================================================================

drop policy if exists "room_members_delete_owner" on public.room_members;
create policy "room_members_delete_moderator"
  on public.room_members
  for delete
  to authenticated
  using (
    public.can_moderate_room_member_target(room_id, auth.uid(), user_id)
  );

drop policy if exists "room_members_update_owner" on public.room_members;
create policy "room_members_update_moderator"
  on public.room_members
  for update
  to authenticated
  using (
    public.can_moderate_room_member_target(room_id, auth.uid(), user_id)
  )
  with check (
    public.can_moderate_room_member_target(room_id, auth.uid(), user_id)
  );

drop policy if exists "room_members_select_owner" on public.room_members;
create policy "room_members_select_moderator"
  on public.room_members
  for select
  to authenticated
  using (
    public.can_moderate_trade_room(room_id, auth.uid())
  );

-- =============================================================================
-- 4. room_bans
-- =============================================================================

drop policy if exists "room_bans_select_owner" on public.room_bans;
create policy "room_bans_select_moderator"
  on public.room_bans
  for select
  to authenticated
  using (
    public.can_moderate_trade_room(room_id, auth.uid())
  );

drop policy if exists "room_bans_insert_owner" on public.room_bans;
create policy "room_bans_insert_moderator"
  on public.room_bans
  for insert
  to authenticated
  with check (
    banned_by = auth.uid()
    and public.can_moderate_room_member_target(room_id, auth.uid(), user_id)
  );

drop policy if exists "room_bans_delete_owner" on public.room_bans;
create policy "room_bans_delete_moderator"
  on public.room_bans
  for delete
  to authenticated
  using (
    public.can_moderate_trade_room(room_id, auth.uid())
  );

-- =============================================================================
-- 5. room_member_tag_assignments — moderators assign non-elevated tags
-- =============================================================================

drop policy if exists "room_member_tag_assignments_insert_owner" on public.room_member_tag_assignments;
create policy "room_member_tag_assignments_insert_moderator"
  on public.room_member_tag_assignments
  for insert
  to authenticated
  with check (
    public.can_assign_room_member_tag(room_id, auth.uid(), tag_id)
    and exists (
      select 1
      from public.room_members m
      where m.room_id = room_member_tag_assignments.room_id
        and m.user_id = room_member_tag_assignments.user_id
        and m.left_at is null
    )
    and exists (
      select 1
      from public.room_member_tags t
      where t.id = room_member_tag_assignments.tag_id
        and t.room_id = room_member_tag_assignments.room_id
    )
  );

drop policy if exists "room_member_tag_assignments_delete_owner" on public.room_member_tag_assignments;
create policy "room_member_tag_assignments_delete_moderator"
  on public.room_member_tag_assignments
  for delete
  to authenticated
  using (
    public.can_assign_room_member_tag(room_id, auth.uid(), tag_id)
  );
