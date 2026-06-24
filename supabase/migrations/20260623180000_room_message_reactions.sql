-- Trade Room message reactions (V1: 👍 🔥 😂 ‼️). Trade Rooms only; no notifications.

create table if not exists public.room_message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.room_messages (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  reaction text not null,
  created_at timestamptz not null default now(),
  constraint room_message_reactions_reaction_check
    check (reaction in ('👍', '🔥', '😂', '‼️')),
  constraint room_message_reactions_unique unique (message_id, user_id, reaction)
);

create index if not exists room_message_reactions_message_id_idx
  on public.room_message_reactions (message_id);

create index if not exists room_message_reactions_user_id_idx
  on public.room_message_reactions (user_id);

alter table public.room_message_reactions enable row level security;

drop policy if exists "room_message_reactions_select_member" on public.room_message_reactions;
create policy "room_message_reactions_select_member"
  on public.room_message_reactions
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.room_messages rm
      where rm.id = message_id
        and public.is_active_room_member(rm.room_id, auth.uid())
    )
  );

drop policy if exists "room_message_reactions_insert_member" on public.room_message_reactions;
create policy "room_message_reactions_insert_member"
  on public.room_message_reactions
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.room_messages rm
      where rm.id = message_id
        and public.is_active_room_member(rm.room_id, auth.uid())
    )
  );

drop policy if exists "room_message_reactions_delete_own" on public.room_message_reactions;
create policy "room_message_reactions_delete_own"
  on public.room_message_reactions
  for delete
  to authenticated
  using (
    user_id = auth.uid()
    and exists (
      select 1
      from public.room_messages rm
      where rm.id = message_id
        and public.is_active_room_member(rm.room_id, auth.uid())
    )
  );

grant select, insert, delete on table public.room_message_reactions to authenticated;

create or replace function public.rate_limit_room_message_reactions_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return NEW;
  end if;

  perform public.rate_limit_hit('like');
  return NEW;
end;
$$;

drop trigger if exists rate_limit_room_message_reactions_before_insert
  on public.room_message_reactions;
create trigger rate_limit_room_message_reactions_before_insert
  before insert on public.room_message_reactions
  for each row
  execute function public.rate_limit_room_message_reactions_before_insert();
