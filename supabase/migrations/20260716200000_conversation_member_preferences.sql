-- Per-user, per-conversation notification preferences (DM + group chats).
-- Missing row = notifications enabled (unmuted).

create table if not exists public.conversation_member_preferences (
  user_id uuid not null references public.profiles (id) on delete cascade,
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  notifications_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint conversation_member_preferences_pkey
    primary key (user_id, conversation_id)
);

create index if not exists conversation_member_preferences_user_id_idx
  on public.conversation_member_preferences (user_id);

create index if not exists conversation_member_preferences_muted_idx
  on public.conversation_member_preferences (user_id, conversation_id)
  where notifications_enabled = false;

comment on table public.conversation_member_preferences is
  'Per-conversation mute for DM/group message badges and notifications. Missing row = enabled.';

create or replace function public.conversation_member_preferences_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists conversation_member_preferences_set_updated_at_trigger
  on public.conversation_member_preferences;
create trigger conversation_member_preferences_set_updated_at_trigger
  before update on public.conversation_member_preferences
  for each row
  execute function public.conversation_member_preferences_set_updated_at();

alter table public.conversation_member_preferences enable row level security;

drop policy if exists "conversation_member_prefs_select_self"
  on public.conversation_member_preferences;
create policy "conversation_member_prefs_select_self"
  on public.conversation_member_preferences
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "conversation_member_prefs_insert_self"
  on public.conversation_member_preferences;
create policy "conversation_member_prefs_insert_self"
  on public.conversation_member_preferences
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.is_conversation_participant(conversation_id, auth.uid())
  );

drop policy if exists "conversation_member_prefs_update_self"
  on public.conversation_member_preferences;
create policy "conversation_member_prefs_update_self"
  on public.conversation_member_preferences
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and public.is_conversation_participant(conversation_id, auth.uid())
  );

drop policy if exists "conversation_member_prefs_delete_self"
  on public.conversation_member_preferences;
create policy "conversation_member_prefs_delete_self"
  on public.conversation_member_preferences
  for delete
  to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete
  on table public.conversation_member_preferences
  to authenticated;
