-- Per-invoice referral commissions (webhook idempotency via stripe_invoice_id)
create table if not exists public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_user_id uuid not null references public.profiles (id) on delete cascade,
  referred_user_id uuid not null references public.profiles (id) on delete cascade,
  amount_earned numeric not null default 0,
  stripe_customer_id text,
  stripe_subscription_id text,
  stripe_invoice_id text,
  created_at timestamptz not null default now()
);

create unique index if not exists referrals_stripe_invoice_id_uidx
  on public.referrals (stripe_invoice_id)
  where stripe_invoice_id is not null;

create index if not exists referrals_referrer_user_id_idx
  on public.referrals (referrer_user_id);

create index if not exists referrals_referred_user_id_idx
  on public.referrals (referred_user_id);
