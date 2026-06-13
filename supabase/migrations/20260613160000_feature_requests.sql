-- Beta feature requests: submissions from beta testers + admin triage.

create table if not exists public.feature_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  description text not null,
  status text not null default 'open',
  created_at timestamptz not null default now(),
  constraint feature_requests_status_ck check (
    status in ('open', 'planned', 'completed')
  )
);

create index if not exists feature_requests_user_id_created_at_idx
  on public.feature_requests (user_id, created_at desc);

create index if not exists feature_requests_status_created_at_idx
  on public.feature_requests (status, created_at desc);

alter table public.feature_requests enable row level security;

drop policy if exists "feature_requests_select_own" on public.feature_requests;
drop policy if exists "feature_requests_insert_beta" on public.feature_requests;
drop policy if exists "feature_requests_admin_select" on public.feature_requests;
drop policy if exists "feature_requests_admin_update" on public.feature_requests;

create policy "feature_requests_select_own"
  on public.feature_requests
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "feature_requests_insert_beta"
  on public.feature_requests
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and coalesce(p.is_beta_tester, false) = true
    )
    and coalesce(trim(title), '') <> ''
    and coalesce(trim(description), '') <> ''
  );

create policy "feature_requests_admin_select"
  on public.feature_requests
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  );

create policy "feature_requests_admin_update"
  on public.feature_requests
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

grant select, insert on table public.feature_requests to authenticated;
grant update on table public.feature_requests to authenticated;

comment on table public.feature_requests is
  'Beta tester feature requests submitted from /beta.';
