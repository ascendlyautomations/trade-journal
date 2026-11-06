-- Trade Room live broadcast: voice mode + video source metadata (session-scoped, BFF-only).

alter table public.room_live_broadcasts
  add column if not exists voice_mode text not null default 'broadcast_only';

alter table public.room_live_broadcasts
  drop constraint if exists room_live_broadcasts_voice_mode_check;

alter table public.room_live_broadcasts
  add constraint room_live_broadcasts_voice_mode_check
  check (voice_mode in ('broadcast_only', 'open_voice'));

alter table public.room_live_broadcasts
  add column if not exists video_source text not null default 'screen';

alter table public.room_live_broadcasts
  drop constraint if exists room_live_broadcasts_video_source_check;

alter table public.room_live_broadcasts
  add constraint room_live_broadcasts_video_source_check
  check (video_source in ('screen', 'camera'));

comment on column public.room_live_broadcasts.voice_mode is
  'broadcast_only: only broadcaster publishes audio; open_voice: viewers may join conversation via server grant.';

comment on column public.room_live_broadcasts.video_source is
  'Primary video source the broadcaster selected at go-live (screen or camera).';
