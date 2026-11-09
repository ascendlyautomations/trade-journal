-- Allow OBS as a session video_source (program video via LiveKit Ingress).

alter table public.room_live_broadcasts
  drop constraint if exists room_live_broadcasts_video_source_check;

alter table public.room_live_broadcasts
  add constraint room_live_broadcasts_video_source_check
  check (video_source in ('screen', 'camera', 'obs'));

comment on column public.room_live_broadcasts.video_source is
  'Primary video pipeline: screen, camera (browser WebRTC), or obs (Ingress program feed).';
