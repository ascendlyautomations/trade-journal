-- Trade Room member tags (room-scoped labels; V1 display-only).
-- Reuses existing room_bans + room_members moderation — no duplicate ban system.

-- =============================================================================
-- Tables
-- =============================================================================

create table if not exists public.room_member_tags (
  id uuid primary key default extensions.uuid_generate_v4(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  name text not null,
  color_key text not null default 'accent',
  is_preset boolean not null default false,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint room_member_tags_name_not_blank check (char_length(trim(name)) > 0)
);

create unique index if not exists room_member_tags_name_room_unique_idx
  on public.room_member_tags (room_id, lower(trim(name)));

create index if not exists room_member_tags_room_id_idx
  on public.room_member_tags (room_id);

comment on table public.room_member_tags is
  'Room-scoped member labels (display-only in V1). Owner-managed.';

create table if not exists public.room_member_tag_assignments (
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  tag_id uuid not null references public.room_member_tags (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (room_id, user_id, tag_id)
);

create index if not exists room_member_tag_assignments_room_user_idx
  on public.room_member_tag_assignments (room_id, user_id);

create index if not exists room_member_tag_assignments_tag_idx
  on public.room_member_tag_assignments (tag_id);

comment on table public.room_member_tag_assignments is
  'Many-to-many room member tag assignments. Cascades when tag or member row is removed.';

-- =============================================================================
-- Seed preset tags (owner-only entry point)
-- =============================================================================

create or replace function public.ensure_room_member_tags_defaults(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  preset_names text[] := array[
    'Admin', 'Moderator', 'Mentor', 'Verified', 'Top Trader', 'Funded',
    'Live Trader', 'Futures', 'Options', 'Crypto', 'New Member'
  ];
  preset_colors text[] := array[
    'purple', 'purple', 'blue', 'teal', 'orange', 'green',
    'green', 'blue', 'orange', 'orange', 'gray'
  ];
  i int;
begin
  if not public.is_room_owner(p_room_id, auth.uid()) then
    raise exception 'not authorized to seed room member tags';
  end if;

  if exists (
    select 1 from public.room_member_tags t where t.room_id = p_room_id
  ) then
    return;
  end if;

  for i in 1..array_length(preset_names, 1) loop
    insert into public.room_member_tags (
      room_id, name, color_key, is_preset, created_by
    )
    values (
      p_room_id,
      preset_names[i],
      preset_colors[i],
      true,
      auth.uid()
    );
  end loop;
end;
$$;

comment on function public.ensure_room_member_tags_defaults(uuid) is
  'Inserts default preset member tags once per room. Owner-only (security definer gate).';

revoke all on function public.ensure_room_member_tags_defaults(uuid) from public;
grant execute on function public.ensure_room_member_tags_defaults(uuid) to authenticated;

-- =============================================================================
-- RLS: room_member_tags
-- =============================================================================

alter table public.room_member_tags enable row level security;

drop policy if exists "room_member_tags_select_member" on public.room_member_tags;
create policy "room_member_tags_select_member"
  on public.room_member_tags
  for select
  to authenticated
  using (
    public.is_active_room_member(room_id, auth.uid())
    or public.is_room_owner(room_id, auth.uid())
  );

drop policy if exists "room_member_tags_insert_owner" on public.room_member_tags;
create policy "room_member_tags_insert_owner"
  on public.room_member_tags
  for insert
  to authenticated
  with check (
    public.is_room_owner(room_id, auth.uid())
    and created_by = auth.uid()
  );

drop policy if exists "room_member_tags_update_owner" on public.room_member_tags;
create policy "room_member_tags_update_owner"
  on public.room_member_tags
  for update
  to authenticated
  using (public.is_room_owner(room_id, auth.uid()))
  with check (public.is_room_owner(room_id, auth.uid()));

drop policy if exists "room_member_tags_delete_owner" on public.room_member_tags;
create policy "room_member_tags_delete_owner"
  on public.room_member_tags
  for delete
  to authenticated
  using (public.is_room_owner(room_id, auth.uid()));

-- =============================================================================
-- RLS: room_member_tag_assignments
-- =============================================================================

alter table public.room_member_tag_assignments enable row level security;

drop policy if exists "room_member_tag_assignments_select_member" on public.room_member_tag_assignments;
create policy "room_member_tag_assignments_select_member"
  on public.room_member_tag_assignments
  for select
  to authenticated
  using (
    public.is_active_room_member(room_id, auth.uid())
    or public.is_room_owner(room_id, auth.uid())
  );

drop policy if exists "room_member_tag_assignments_insert_owner" on public.room_member_tag_assignments;
create policy "room_member_tag_assignments_insert_owner"
  on public.room_member_tag_assignments
  for insert
  to authenticated
  with check (
    public.is_room_owner(room_id, auth.uid())
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
create policy "room_member_tag_assignments_delete_owner"
  on public.room_member_tag_assignments
  for delete
  to authenticated
  using (public.is_room_owner(room_id, auth.uid()));
