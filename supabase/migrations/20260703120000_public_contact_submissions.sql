-- Public marketing contact form submissions (no auth required; inserted via API service role).
create table if not exists public.public_contact_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete set null,
  name text not null,
  email text not null,
  category text not null,
  subject text not null,
  message text not null,
  created_at timestamptz not null default now(),
  constraint public_contact_submissions_category_ck
    check (category in ('general', 'billing', 'partnership', 'business'))
);

create index if not exists public_contact_submissions_created_at_idx
  on public.public_contact_submissions (created_at desc);

alter table public.public_contact_submissions enable row level security;

create policy "public_contact_submissions_admin_select"
  on public.public_contact_submissions for select
  to authenticated
  using (
    exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  );
