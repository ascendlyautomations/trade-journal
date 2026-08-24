-- Phase F2 security correction: enforce message_id / room_id integrity on reactions.
-- Does not modify room bootstrap RPC or publication membership.

-- ---------------------------------------------------------------------------
-- 1. Integrity trigger (SECURITY INVOKER — respects room_messages RLS)
-- ---------------------------------------------------------------------------
create or replace function public.room_message_reactions_enforce_message_room_integrity()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_authoritative_room_id uuid;
begin
  select rm.room_id
    into v_authoritative_room_id
  from public.room_messages rm
  where rm.id = new.message_id;

  if v_authoritative_room_id is null then
    raise exception
      'room_message_reactions: message % not found or not accessible',
      new.message_id
      using errcode = '23503';
  end if;

  if new.room_id is not null
     and new.room_id is distinct from v_authoritative_room_id then
    raise exception
      'room_message_reactions: room_id % does not match message % (room %)',
      new.room_id,
      new.message_id,
      v_authoritative_room_id
      using errcode = '23514';
  end if;

  new.room_id := v_authoritative_room_id;
  return new;
end;
$$;

comment on function public.room_message_reactions_enforce_message_room_integrity() is
  'Derives room_id from room_messages for each reaction row. Rejects client-supplied room_id mismatches. SECURITY INVOKER so message lookup is subject to room_messages RLS (no cross-room oracle).';

revoke all on function public.room_message_reactions_enforce_message_room_integrity() from public;

drop trigger if exists room_message_reactions_set_room_id
  on public.room_message_reactions;

drop function if exists public.room_message_reactions_set_room_id();

drop trigger if exists room_message_reactions_enforce_message_room_integrity
  on public.room_message_reactions;

create trigger room_message_reactions_enforce_message_room_integrity
  before insert or update of message_id, room_id
  on public.room_message_reactions
  for each row
  execute function public.room_message_reactions_enforce_message_room_integrity();

-- ---------------------------------------------------------------------------
-- 2. Composite FK (message_id, room_id) → room_messages(id, room_id)
--    room_messages.id is PK so (id, room_id) is unique; adds DB-level guard.
-- ---------------------------------------------------------------------------
create unique index if not exists room_messages_id_room_id_uidx
  on public.room_messages (id, room_id);

alter table public.room_message_reactions
  drop constraint if exists room_message_reactions_message_room_fkey;

alter table public.room_message_reactions
  add constraint room_message_reactions_message_room_fkey
  foreign key (message_id, room_id)
  references public.room_messages (id, room_id)
  on delete cascade;

-- ---------------------------------------------------------------------------
-- 3. RLS — cached auth.uid() + message/room consistency on INSERT
-- ---------------------------------------------------------------------------
drop policy if exists "room_message_reactions_select_member" on public.room_message_reactions;
create policy "room_message_reactions_select_member"
  on public.room_message_reactions
  for select
  to authenticated
  using (
    public.is_active_room_member(room_id, (select auth.uid()))
  );

drop policy if exists "room_message_reactions_insert_member" on public.room_message_reactions;
create policy "room_message_reactions_insert_member"
  on public.room_message_reactions
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and public.is_active_room_member(room_id, (select auth.uid()))
    and exists (
      select 1
      from public.room_messages rm
      where rm.id = message_id
        and rm.room_id = room_id
    )
  );

drop policy if exists "room_message_reactions_delete_own" on public.room_message_reactions;
create policy "room_message_reactions_delete_own"
  on public.room_message_reactions
  for delete
  to authenticated
  using (
    user_id = (select auth.uid())
    and public.is_active_room_member(room_id, (select auth.uid()))
  );

-- ---------------------------------------------------------------------------
-- 4. Backfill repair — fix any rows that slipped in before this migration
-- ---------------------------------------------------------------------------
update public.room_message_reactions r
set room_id = rm.room_id
from public.room_messages rm
where rm.id = r.message_id
  and r.room_id is distinct from rm.room_id;
