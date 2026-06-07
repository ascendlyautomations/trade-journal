-- Phase 2: Trade Room security — RLS on public.room_messages only.
-- Depends on Phase 1: public.is_active_room_member(uuid, uuid)
-- Does not modify rooms, room_members, room_presence, or room_sections.

-- Helper: room owner check (reads rooms; does not alter rooms table).
create or replace function public.is_room_owner(
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
    from public.rooms r
    where r.id = p_room_id
      and r.owner_user_id = p_user_id
  );
$$;

comment on function public.is_room_owner(uuid, uuid) is
  'True when p_user_id owns p_room_id (rooms.owner_user_id). Legacy rooms with NULL owner never match.';

-- BEFORE UPDATE trigger: safest seen_by path without app/RPC changes.
-- RLS grants members a narrow UPDATE policy on others'' messages; this trigger
-- rejects changes to any column other than seen_by unless author or room owner.
create or replace function public.room_messages_before_update_guard()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  -- Author may update own message content/fields; pinned changes require owner.
  if old.user_id = auth.uid() then
    if old.pinned is distinct from new.pinned
       and not public.is_room_owner(new.room_id, auth.uid()) then
      raise exception 'only room owner may change pinned';
    end if;
    return new;
  end if;

  -- Room owner may update any message in owned rooms (pin / moderation).
  if public.is_room_owner(new.room_id, auth.uid()) then
    return new;
  end if;

  -- Active members may only mutate seen_by on someone else''s message.
  if public.is_active_room_member(new.room_id, auth.uid()) then
    if old.room_id is distinct from new.room_id
       or old.user_id is distinct from new.user_id
       or old.content is distinct from new.content
       or old.image_url is distinct from new.image_url
       or old.trade_id is distinct from new.trade_id
       or old.section_id is distinct from new.section_id
       or old.type is distinct from new.type
       or old.pinned is distinct from new.pinned
       or old.pinned_trade_id is distinct from new.pinned_trade_id
       or old.created_at is distinct from new.created_at
    then
      raise exception 'members may only update seen_by on others'' messages';
    end if;
    return new;
  end if;

  return new;
end;
$$;

drop trigger if exists room_messages_before_update_guard on public.room_messages;

create trigger room_messages_before_update_guard
  before update on public.room_messages
  for each row
  execute function public.room_messages_before_update_guard();

alter table public.room_messages enable row level security;

-- SELECT: active room members only (chat, unread badges, realtime hydrate)
drop policy if exists "room_messages_select_member" on public.room_messages;
create policy "room_messages_select_member"
  on public.room_messages
  for select
  to authenticated
  using (
    public.is_active_room_member(room_id, auth.uid())
  );

-- SELECT: author read own messages (free-plan limit count in lib/freePlanLimits.ts)
drop policy if exists "room_messages_select_own" on public.room_messages;
create policy "room_messages_select_own"
  on public.room_messages
  for select
  to authenticated
  using (
    user_id = auth.uid()
  );

-- INSERT: active members; must post as self
drop policy if exists "room_messages_insert_member" on public.room_messages;
create policy "room_messages_insert_member"
  on public.room_messages
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
  );

-- UPDATE: message author (own rows)
drop policy if exists "room_messages_update_author" on public.room_messages;
create policy "room_messages_update_author"
  on public.room_messages
  for update
  to authenticated
  using (
    user_id = auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
  )
  with check (
    user_id = auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
  );

-- UPDATE: room owner moderation (pin, future field edits)
drop policy if exists "room_messages_update_owner" on public.room_messages;
create policy "room_messages_update_owner"
  on public.room_messages
  for update
  to authenticated
  using (
    public.is_room_owner(room_id, auth.uid())
  )
  with check (
    public.is_room_owner(room_id, auth.uid())
  );

-- UPDATE: seen_by — active members on others'' messages (column guard via trigger)
drop policy if exists "room_messages_update_seen_by_member" on public.room_messages;
create policy "room_messages_update_seen_by_member"
  on public.room_messages
  for update
  to authenticated
  using (
    user_id <> auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
  )
  with check (
    user_id <> auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
  );

-- DELETE: message author
drop policy if exists "room_messages_delete_author" on public.room_messages;
create policy "room_messages_delete_author"
  on public.room_messages
  for delete
  to authenticated
  using (
    user_id = auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
  );

-- DELETE: room owner moderation
drop policy if exists "room_messages_delete_owner" on public.room_messages;
create policy "room_messages_delete_owner"
  on public.room_messages
  for delete
  to authenticated
  using (
    public.is_room_owner(room_id, auth.uid())
  );

-- =============================================================================
-- ROLLBACK (run manually to revert this migration)
-- =============================================================================
-- drop policy if exists "room_messages_select_member" on public.room_messages;
-- drop policy if exists "room_messages_select_own" on public.room_messages;
-- drop policy if exists "room_messages_insert_member" on public.room_messages;
-- drop policy if exists "room_messages_update_author" on public.room_messages;
-- drop policy if exists "room_messages_update_owner" on public.room_messages;
-- drop policy if exists "room_messages_update_seen_by_member" on public.room_messages;
-- drop policy if exists "room_messages_delete_author" on public.room_messages;
-- drop policy if exists "room_messages_delete_owner" on public.room_messages;
--
-- drop trigger if exists room_messages_before_update_guard on public.room_messages;
-- drop function if exists public.room_messages_before_update_guard();
--
-- alter table public.room_messages disable row level security;
--
-- drop function if exists public.is_room_owner(uuid, uuid);
