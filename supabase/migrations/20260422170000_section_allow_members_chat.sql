-- Per-channel chat permission; room-level column removed from app usage.
alter table public.room_sections
  add column if not exists allow_members_chat boolean not null default true;

alter table public.rooms
  drop column if exists allow_members_chat;
