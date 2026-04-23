alter table public.rooms
  add column if not exists allow_members_chat boolean not null default true;
