-- Per-room notification preference for Trade Room members.

alter table public.room_members
  add column if not exists notification_enabled boolean not null default true;

comment on column public.room_members.notification_enabled is
  'When true, member receives room_message notifications for this room.';

update public.room_members
set notification_enabled = true
where notification_enabled is distinct from true;
