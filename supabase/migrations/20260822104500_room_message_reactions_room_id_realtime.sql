-- Phase F2: room-scoped Realtime filter for room_message_reactions.
-- Denormalize room_id so clients subscribe with room_id=eq.{roomId}
-- instead of message_id=in.(...) which fails on Realtime for multiple UUIDs.

alter table public.room_message_reactions
  add column if not exists room_id uuid references public.rooms (id) on delete cascade;

update public.room_message_reactions r
set room_id = rm.room_id
from public.room_messages rm
where rm.id = r.message_id
  and r.room_id is null;

alter table public.room_message_reactions
  alter column room_id set not null;

create index if not exists room_message_reactions_room_id_idx
  on public.room_message_reactions (room_id);

create or replace function public.room_message_reactions_set_room_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.room_id is not null then
    return NEW;
  end if;

  select rm.room_id into NEW.room_id
  from public.room_messages rm
  where rm.id = NEW.message_id;

  if NEW.room_id is null then
    raise exception 'room_message_reactions: message % not found', NEW.message_id;
  end if;

  return NEW;
end;
$$;

drop trigger if exists room_message_reactions_set_room_id
  on public.room_message_reactions;
create trigger room_message_reactions_set_room_id
  before insert on public.room_message_reactions
  for each row
  execute function public.room_message_reactions_set_room_id();

-- Tighten RLS: direct room_id membership check (Realtime-friendly).
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

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.room_message_reactions;
    exception
      when duplicate_object then null;
    end;
  end if;
end $$;
