-- UGC content reports for in-app moderation (App Store Guideline 1.2).

create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_user_id uuid not null references auth.users (id) on delete cascade,
  target_type text not null,
  target_id text not null,
  reported_user_id uuid references auth.users (id) on delete set null,
  reason text not null,
  details text,
  status text not null default 'open',
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users (id) on delete set null,
  constraint content_reports_target_type_ck check (
    target_type in (
      'user',
      'trade',
      'post',
      'reel',
      'story',
      'achievement',
      'comment',
      'direct_message',
      'trade_room',
      'trade_room_message'
    )
  ),
  constraint content_reports_reason_ck check (
    reason in (
      'harassment',
      'spam',
      'scam',
      'inappropriate',
      'hate',
      'impersonation',
      'dangerous',
      'other'
    )
  ),
  constraint content_reports_status_ck check (
    status in ('open', 'reviewing', 'resolved', 'dismissed')
  ),
  constraint content_reports_details_len_ck check (
    details is null or char_length(details) <= 2000
  ),
  constraint content_reports_target_id_len_ck check (
    char_length(trim(target_id)) >= 1
  )
);

comment on table public.content_reports is
  'User-submitted UGC moderation reports. Reporter identity is always auth.uid().';

create index if not exists content_reports_status_created_at_idx
  on public.content_reports (status, created_at desc);

create index if not exists content_reports_reporter_created_at_idx
  on public.content_reports (reporter_user_id, created_at desc);

create index if not exists content_reports_reported_user_created_at_idx
  on public.content_reports (reported_user_id, created_at desc)
  where reported_user_id is not null;

-- One active report per reporter + target (open/reviewing).
create unique index if not exists content_reports_active_unique_idx
  on public.content_reports (reporter_user_id, target_type, target_id)
  where status in ('open', 'reviewing');

alter table public.content_reports enable row level security;

drop policy if exists content_reports_insert_own on public.content_reports;
drop policy if exists content_reports_select_own on public.content_reports;
drop policy if exists content_reports_admin_select on public.content_reports;
drop policy if exists content_reports_admin_update on public.content_reports;

create policy content_reports_insert_own
  on public.content_reports
  for insert
  to authenticated
  with check (
    reporter_user_id = auth.uid()
    and (
      target_type <> 'user'
      or target_id <> auth.uid()::text
    )
    and (
      reported_user_id is null
      or reported_user_id <> auth.uid()
    )
  );

-- Reporters may read only their own submissions (optional transparency).
create policy content_reports_select_own
  on public.content_reports
  for select
  to authenticated
  using (reporter_user_id = auth.uid());

create policy content_reports_admin_select
  on public.content_reports
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  );

create policy content_reports_admin_update
  on public.content_reports
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
    and reviewed_by = auth.uid()
  );

revoke all on table public.content_reports from anon;
grant select, insert on table public.content_reports to authenticated;
grant all on table public.content_reports to service_role;
