-- Trade Room screen-share broadcast (LiveKit `tt/{roomId}/broadcast`), Phase 1.

create table if not exists public.room_live_broadcasts (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  broadcaster_user_id uuid not null,
  started_at timestamptz not null default timezone('utc', now()),
  ended_at timestamptz,
  ended_reason text,
  last_livekit_signal_at timestamptz
);

create unique index if not exists room_live_broadcasts_one_active_per_room_idx
  on public.room_live_broadcasts (room_id)
  where ended_at is null;

create index if not exists room_live_broadcasts_room_started_idx
  on public.room_live_broadcasts (room_id, started_at desc);

alter table public.room_live_broadcasts enable row level security;

comment on table public.room_live_broadcasts is
  'At most one active row per room (partial unique index). Server/BFF only — no client policies.';

-- End broadcasts when a member is banned (best-effort; LiveKit disconnect handled separately).
create or replace function public.room_bans_after_insert_end_live_broadcast()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.room_live_broadcasts
  set
    ended_at = timezone('utc', now()),
    ended_reason = 'ban'
  where room_id = new.room_id
    and broadcaster_user_id = new.user_id
    and ended_at is null;
  return new;
end;
$$;

drop trigger if exists room_bans_end_live_broadcast on public.room_bans;
create trigger room_bans_end_live_broadcast
  after insert on public.room_bans
  for each row
  execute function public.room_bans_after_insert_end_live_broadcast();
