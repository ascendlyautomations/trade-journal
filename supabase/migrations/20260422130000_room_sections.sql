-- Trade Room channels (subsections); legacy messages keep section_id null.
create table if not exists public.room_sections (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  name text not null,
  position integer not null default 0,
  created_at timestamptz default now()
);

create index if not exists room_sections_room_id_position_idx
  on public.room_sections (room_id, position);

alter table public.room_messages
  add column if not exists section_id uuid references public.room_sections (id) on delete set null;

create index if not exists room_messages_room_section_idx
  on public.room_messages (room_id, section_id);
