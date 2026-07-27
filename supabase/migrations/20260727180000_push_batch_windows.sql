-- Durable push batch / room-digest windows for serverless coalescing.
-- Service-role only. No client access.

create table if not exists public.push_batch_windows (
  recipient_user_id uuid not null references auth.users (id) on delete cascade,
  batch_kind text not null,
  batch_key text not null,
  window_ends_at timestamptz not null,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (recipient_user_id, batch_kind, batch_key),
  constraint push_batch_windows_kind_check check (
    batch_kind in ('like', 'follow', 'room_digest')
  )
);

create index if not exists push_batch_windows_due_idx
  on public.push_batch_windows (window_ends_at);

comment on table public.push_batch_windows is
  'Open like/follow/room push batch windows. Deleted after flush.';

alter table public.push_batch_windows enable row level security;

revoke all on table public.push_batch_windows from anon, authenticated;
grant all on table public.push_batch_windows to service_role;
