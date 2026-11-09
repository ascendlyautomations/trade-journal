-- OBS two-stage lifecycle: private preparation vs public live.

alter table public.room_live_broadcasts
  add column if not exists visibility text not null default 'public'
    check (visibility in ('public', 'preparing'));

comment on column public.room_live_broadcasts.visibility is
  'public = discoverable live stream; preparing = host-only OBS setup (no viewers/notifications).';

-- Exactly one fan-out per session when going public.
alter table public.room_live_broadcasts
  add column if not exists go_live_notified_at timestamptz;

comment on column public.room_live_broadcasts.go_live_notified_at is
  'Set when room go-live push fan-out ran; prevents duplicate notifications.';

-- Existing rows were always treated as public.
update public.room_live_broadcasts
set visibility = 'public'
where visibility is distinct from 'public';
