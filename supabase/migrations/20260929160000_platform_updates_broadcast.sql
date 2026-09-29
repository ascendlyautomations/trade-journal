-- Admin platform updates (What's New) + optional broadcast push delivery.

create table if not exists public.platform_updates (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 1 and 200),
  body text not null check (char_length(trim(body)) between 1 and 8000),
  category text not null check (
    category in ('announcement', 'new_feature', 'improvement', 'fix', 'maintenance')
  ),
  destination text not null,
  send_push boolean not null default false,
  status text not null default 'draft' check (
    status in ('draft', 'scheduled', 'published', 'cancelled')
  ),
  publish_at timestamptz null,
  published_at timestamptz null,
  created_by uuid null references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_updates_publish_at_when_scheduled check (
    status <> 'scheduled' or publish_at is not null
  )
);

create index if not exists platform_updates_status_publish_at_idx
  on public.platform_updates (status, publish_at);

create index if not exists platform_updates_published_at_idx
  on public.platform_updates (published_at desc nulls last)
  where status = 'published';

comment on table public.platform_updates is
  'Admin-authored product updates shown on What''s New; optional broadcast APNs.';

create table if not exists public.platform_update_broadcasts (
  id uuid primary key default gen_random_uuid(),
  update_id uuid not null references public.platform_updates (id) on delete cascade,
  status text not null default 'pending' check (
    status in ('pending', 'sending', 'sent', 'partial_failure', 'failed')
  ),
  attempted_count integer not null default 0 check (attempted_count >= 0),
  success_count integer not null default 0 check (success_count >= 0),
  failed_count integer not null default 0 check (failed_count >= 0),
  cursor_token_id uuid null,
  started_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default now(),
  constraint platform_update_broadcasts_update_id_key unique (update_id)
);

comment on table public.platform_update_broadcasts is
  'Idempotent broadcast job per published update (batched APNs to all device tokens).';

alter table public.platform_updates enable row level security;
alter table public.platform_update_broadcasts enable row level security;

-- Authenticated users may read published updates only (BFF also uses service role).
drop policy if exists platform_updates_select_published on public.platform_updates;
create policy platform_updates_select_published
  on public.platform_updates
  for select
  to authenticated
  using (status = 'published');

-- No client writes; admin BFF uses service role.
