-- Session-scoped broadcast interactive state (hands, invites, blocks, speaker grants).
-- BFF/service-role only — no client RLS policies.

create table if not exists public.room_live_broadcast_hands (
  broadcast_session_id uuid not null references public.room_live_broadcasts (id) on delete cascade,
  user_id uuid not null,
  raised_at timestamptz not null default timezone('utc', now()),
  primary key (broadcast_session_id, user_id)
);

create index if not exists room_live_broadcast_hands_session_raised_idx
  on public.room_live_broadcast_hands (broadcast_session_id, raised_at desc);

create table if not exists public.room_live_broadcast_speaker_grants (
  id uuid primary key default gen_random_uuid(),
  broadcast_session_id uuid not null references public.room_live_broadcasts (id) on delete cascade,
  user_id uuid not null,
  granted_by uuid not null,
  granted_at timestamptz not null default timezone('utc', now()),
  revoked_at timestamptz,
  unique (broadcast_session_id, user_id)
);

create index if not exists room_live_broadcast_speaker_grants_active_idx
  on public.room_live_broadcast_speaker_grants (broadcast_session_id)
  where revoked_at is null;

create table if not exists public.room_live_broadcast_session_blocks (
  broadcast_session_id uuid not null references public.room_live_broadcasts (id) on delete cascade,
  user_id uuid not null,
  blocked_by uuid not null,
  blocked_at timestamptz not null default timezone('utc', now()),
  primary key (broadcast_session_id, user_id)
);

create table if not exists public.room_live_broadcast_invitations (
  id uuid primary key default gen_random_uuid(),
  broadcast_session_id uuid not null references public.room_live_broadcasts (id) on delete cascade,
  user_id uuid not null,
  invited_by uuid not null,
  status text not null default 'pending',
  invited_at timestamptz not null default timezone('utc', now()),
  responded_at timestamptz,
  constraint room_live_broadcast_invitations_status_check
    check (status in ('pending', 'accepted', 'declined', 'revoked'))
);

create unique index if not exists room_live_broadcast_invitations_one_pending_idx
  on public.room_live_broadcast_invitations (broadcast_session_id, user_id)
  where status = 'pending';

alter table public.room_live_broadcast_hands enable row level security;
alter table public.room_live_broadcast_speaker_grants enable row level security;
alter table public.room_live_broadcast_session_blocks enable row level security;
alter table public.room_live_broadcast_invitations enable row level security;

comment on table public.room_live_broadcast_hands is
  'Authoritative raised-hand roster per active broadcast session.';
