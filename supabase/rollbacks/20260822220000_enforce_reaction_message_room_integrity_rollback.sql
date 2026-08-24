-- Rollback: enforce_reaction_message_room_integrity (Phase F2 security correction)
-- Apply manually if reverting 20260822220000_enforce_reaction_message_room_integrity.sql
--
-- NOTE: Does NOT remove room_message_reactions from supabase_realtime.
-- That table may have been published before Phase F2; see
-- 20260822104500_room_message_reactions_room_id_realtime_rollback.sql.

alter table public.room_message_reactions
  drop constraint if exists room_message_reactions_message_room_fkey;

drop index if exists public.room_messages_id_room_id_uidx;

drop trigger if exists room_message_reactions_enforce_message_room_integrity
  on public.room_message_reactions;

drop function if exists public.room_message_reactions_enforce_message_room_integrity();

-- Restore prior Phase F2 trigger (still has client-trust defect — re-apply security fix after rollback).
create or replace function public.room_message_reactions_set_room_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.room_id is not null then
    return new;
  end if;

  select rm.room_id into new.room_id
  from public.room_messages rm
  where rm.id = new.message_id;

  if new.room_id is null then
    raise exception 'room_message_reactions: message % not found', new.message_id;
  end if;

  return new;
end;
$$;

create trigger room_message_reactions_set_room_id
  before insert on public.room_message_reactions
  for each row
  execute function public.room_message_reactions_set_room_id();

drop policy if exists "room_message_reactions_select_member" on public.room_message_reactions;
create policy "room_message_reactions_select_member"
  on public.room_message_reactions
  for select
  to authenticated
  using (public.is_active_room_member(room_id, auth.uid()));

drop policy if exists "room_message_reactions_insert_member" on public.room_message_reactions;
create policy "room_message_reactions_insert_member"
  on public.room_message_reactions
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
  );

drop policy if exists "room_message_reactions_delete_own" on public.room_message_reactions;
create policy "room_message_reactions_delete_own"
  on public.room_message_reactions
  for delete
  to authenticated
  using (
    user_id = auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
  );
