-- Phase 1: affiliate payout requests (no live Stripe payouts yet).

create table if not exists public.affiliate_payout_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  affiliate_id uuid references public.affiliates (id) on delete set null,
  amount numeric(14, 2) not null check (amount > 0),
  status text not null default 'pending'
    constraint affiliate_payout_requests_status_ck
      check (status in ('pending', 'approved', 'paid', 'rejected')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users (id) on delete set null,
  paid_at timestamptz,
  admin_notes text,
  payout_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.affiliate_payout_requests is
  'Affiliate-initiated payout requests; fulfilled later via admin / Stripe.';

create index if not exists affiliate_payout_requests_user_id_created_idx
  on public.affiliate_payout_requests (user_id, created_at desc);

create unique index if not exists affiliate_payout_requests_one_pending_per_user
  on public.affiliate_payout_requests (user_id)
  where status = 'pending';

create or replace function public.set_affiliate_payout_requests_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists affiliate_payout_requests_set_updated_at on public.affiliate_payout_requests;
create trigger affiliate_payout_requests_set_updated_at
  before update on public.affiliate_payout_requests
  for each row
  execute procedure public.set_affiliate_payout_requests_updated_at();

alter table public.affiliate_payout_requests enable row level security;

drop policy if exists "affiliate_payout_requests_select_own" on public.affiliate_payout_requests;
create policy "affiliate_payout_requests_select_own"
  on public.affiliate_payout_requests for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "affiliate_payout_requests_insert_affiliate" on public.affiliate_payout_requests;
create policy "affiliate_payout_requests_insert_affiliate"
  on public.affiliate_payout_requests for insert to authenticated
  with check (
    user_id = auth.uid()
    and affiliate_id is not null
    and affiliate_id = (select a.id from public.affiliates a where a.user_id = auth.uid())
  );

drop policy if exists "affiliate_payout_requests_select_admin" on public.affiliate_payout_requests;
create policy "affiliate_payout_requests_select_admin"
  on public.affiliate_payout_requests for select to authenticated
  using (exists (select 1 from public.admin_users au where au.user_id = auth.uid()));
