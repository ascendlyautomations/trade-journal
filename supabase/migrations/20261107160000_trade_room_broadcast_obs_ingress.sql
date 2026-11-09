-- OBS / LiveKit Ingress metadata for Trade Room broadcast (Phase 1).
-- RTMP stream keys are never stored; only LiveKit ingress id and publisher identity.

alter table public.room_live_broadcasts
  add column if not exists broadcast_source text not null default 'browser'
    check (broadcast_source in ('browser', 'obs'));

alter table public.room_live_broadcasts
  add column if not exists primary_media_publisher_identity text;

alter table public.room_live_broadcasts
  add column if not exists livekit_ingress_id text;

alter table public.room_live_broadcasts
  add column if not exists ingress_status_snapshot text;

comment on column public.room_live_broadcasts.broadcast_source is
  'browser = host publishes via WebRTC client; obs = primary program via LiveKit Ingress.';
comment on column public.room_live_broadcasts.primary_media_publisher_identity is
  'LiveKit participant identity for primary program media (OBS ingress); distinct from broadcaster_user_id.';
comment on column public.room_live_broadcasts.livekit_ingress_id is
  'LiveKit Ingress resource id; stream keys are never persisted.';
comment on column public.room_live_broadcasts.ingress_status_snapshot is
  'Last observed LiveKit IngressState.Status name (e.g. ENDPOINT_PUBLISHING); optional.';
