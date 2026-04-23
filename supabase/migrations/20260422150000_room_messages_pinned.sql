alter table public.room_messages
  add column if not exists pinned boolean not null default false;
