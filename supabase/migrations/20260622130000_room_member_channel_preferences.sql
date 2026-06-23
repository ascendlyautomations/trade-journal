-- Per-channel Trade Room notification preferences (default ON when no row exists).

create table if not exists public.room_member_channel_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  room_id uuid not null references public.rooms (id) on delete cascade,
  section_id uuid not null references public.room_sections (id) on delete cascade,
  notifications_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  constraint room_member_channel_preferences_user_room_section_key
    unique (user_id, room_id, section_id)
);

create index if not exists room_member_channel_preferences_user_room_idx
  on public.room_member_channel_preferences (user_id, room_id);

comment on table public.room_member_channel_preferences is
  'Per-channel mute for Trade Room message notifications. Missing row = notifications enabled.';

alter table public.room_member_channel_preferences enable row level security;

drop policy if exists "room_channel_prefs_select_self"
  on public.room_member_channel_preferences;
create policy "room_channel_prefs_select_self"
  on public.room_member_channel_preferences
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "room_channel_prefs_insert_self"
  on public.room_member_channel_preferences;
create policy "room_channel_prefs_insert_self"
  on public.room_member_channel_preferences
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
  );

drop policy if exists "room_channel_prefs_update_self"
  on public.room_member_channel_preferences;
create policy "room_channel_prefs_update_self"
  on public.room_member_channel_preferences
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
  );

drop policy if exists "room_channel_prefs_delete_self"
  on public.room_member_channel_preferences;
create policy "room_channel_prefs_delete_self"
  on public.room_member_channel_preferences
  for delete
  to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete
  on table public.room_member_channel_preferences
  to authenticated;
