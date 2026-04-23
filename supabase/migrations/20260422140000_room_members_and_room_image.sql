-- Membership for private Trade Rooms; optional room profile image.
create table if not exists public.room_members (
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz default now(),
  primary key (room_id, user_id)
);

create index if not exists room_members_user_id_idx
  on public.room_members (user_id);

alter table public.rooms
  add column if not exists image_url text;
