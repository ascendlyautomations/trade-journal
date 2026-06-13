-- Beta bug reports: user submissions + admin triage.
-- Isolated from support_tickets / feedback_submissions.

create table if not exists public.bug_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  description text not null,
  screenshot_url text,
  page_url text,
  browser_info text,
  severity text not null default 'medium',
  status text not null default 'open',
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint bug_reports_severity_ck check (
    severity in ('low', 'medium', 'high', 'critical')
  ),
  constraint bug_reports_status_ck check (
    status in ('open', 'in_progress', 'resolved')
  )
);

create index if not exists bug_reports_user_id_created_at_idx
  on public.bug_reports (user_id, created_at desc);

create index if not exists bug_reports_status_created_at_idx
  on public.bug_reports (status, created_at desc);

create index if not exists bug_reports_severity_created_at_idx
  on public.bug_reports (severity, created_at desc);

alter table public.bug_reports enable row level security;

drop policy if exists "bug_reports_select_own" on public.bug_reports;
drop policy if exists "bug_reports_insert_own" on public.bug_reports;
drop policy if exists "bug_reports_admin_select" on public.bug_reports;
drop policy if exists "bug_reports_admin_update" on public.bug_reports;

create policy "bug_reports_select_own"
  on public.bug_reports
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "bug_reports_insert_own"
  on public.bug_reports
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and coalesce(trim(title), '') <> ''
    and coalesce(trim(description), '') <> ''
  );

create policy "bug_reports_admin_select"
  on public.bug_reports
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  );

create policy "bug_reports_admin_update"
  on public.bug_reports
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
  );

grant select, insert on table public.bug_reports to authenticated;
grant update on table public.bug_reports to authenticated;

comment on table public.bug_reports is
  'Beta tester bug reports with optional screenshot and auto-captured context.';
