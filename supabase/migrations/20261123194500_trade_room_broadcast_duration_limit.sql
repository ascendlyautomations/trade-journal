-- Server-enforced 2h video broadcast duration + 15m per-broadcaster cooldown (not general voice).

alter table public.room_live_broadcasts
  add column if not exists expires_at timestamptz;

comment on column public.room_live_broadcasts.expires_at is
  'Authoritative end time for video broadcast sessions. BFF/pg_cron ends live rows when expires_at <= now(). NULL during OBS preparation only.';

create index if not exists room_live_broadcasts_duration_expired_due_idx
  on public.room_live_broadcasts (expires_at)
  where ended_at is null and expires_at is not null;

create table if not exists public.room_live_broadcast_broadcaster_cooldowns (
  broadcaster_user_id uuid primary key,
  cooldown_until timestamptz not null,
  updated_at timestamptz not null default timezone('utc', now())
);

comment on table public.room_live_broadcast_broadcaster_cooldowns is
  'Cross-room cooldown after duration_limit — service role only; prevents room-hopping.';

alter table public.room_live_broadcast_broadcaster_cooldowns enable row level security;

-- Duration expiry runs in the existing `process-broadcast-disconnect` BFF handler
-- (also invoked by `livekit-broadcast-disconnect-check` pg_cron every minute).