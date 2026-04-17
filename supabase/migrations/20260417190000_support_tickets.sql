-- Async support tickets (user submit + admin triage). Table may already exist in some environments.
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  email text,
  category text not null,
  subject text not null,
  message text not null,
  screenshot_url text,
  status text not null default 'open',
  priority text not null default 'normal',
  admin_notes text,
  viewed boolean not null default false,
  viewed_at timestamptz,
  viewed_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists support_tickets_user_id_created_at_idx
  on public.support_tickets (user_id, created_at desc);

create index if not exists support_tickets_viewed_created_at_idx
  on public.support_tickets (viewed, created_at desc);

create index if not exists support_tickets_status_created_at_idx
  on public.support_tickets (status, created_at desc);

alter table public.support_tickets enable row level security;

drop policy if exists "support_tickets_select_own" on public.support_tickets;
drop policy if exists "support_tickets_insert_own" on public.support_tickets;
drop policy if exists "support_tickets_admin_select" on public.support_tickets;
drop policy if exists "support_tickets_admin_update" on public.support_tickets;

create policy "support_tickets_select_own"
  on public.support_tickets for select
  to authenticated
  using (user_id = auth.uid());

create policy "support_tickets_insert_own"
  on public.support_tickets for insert
  to authenticated
  with check (user_id = auth.uid());

-- Admins use the same client Supabase session as feedback admin flows.
create policy "support_tickets_admin_select"
  on public.support_tickets for select
  to authenticated
  using (
    exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  );

create policy "support_tickets_admin_update"
  on public.support_tickets for update
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
