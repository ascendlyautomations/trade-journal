-- CSV import support requests (broker/platform CSV assistance for users who cannot import themselves).
-- Run in Supabase SQL editor or via your migration pipeline.

create table if not exists public.csv_support_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade,
  broker_name text,
  notes text,
  csv_file_url text,
  created_at timestamptz not null default now(),
  status text not null default 'new'
    constraint csv_support_requests_status_ck
      check (status in ('new', 'in_progress', 'resolved', 'closed'))
);

comment on table public.csv_support_requests is
  'User requests for help importing CSV trade history from a broker or platform.';

create index if not exists csv_support_requests_user_id_created_at_idx
  on public.csv_support_requests (user_id, created_at desc);

create index if not exists csv_support_requests_status_created_at_idx
  on public.csv_support_requests (status, created_at desc);

alter table public.csv_support_requests enable row level security;

drop policy if exists "csv_support_requests_select_own" on public.csv_support_requests;
drop policy if exists "csv_support_requests_insert_own" on public.csv_support_requests;
drop policy if exists "csv_support_requests_select_admin" on public.csv_support_requests;
drop policy if exists "csv_support_requests_update_admin" on public.csv_support_requests;

create policy "csv_support_requests_select_own"
  on public.csv_support_requests for select
  to authenticated
  using (user_id = auth.uid());

create policy "csv_support_requests_insert_own"
  on public.csv_support_requests for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "csv_support_requests_select_admin"
  on public.csv_support_requests for select
  to authenticated
  using (
    exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  );

create policy "csv_support_requests_update_admin"
  on public.csv_support_requests for update
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
