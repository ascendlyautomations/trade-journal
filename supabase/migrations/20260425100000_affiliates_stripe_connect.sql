-- Stripe Connect onboarding fields (no payout execution yet).

alter table public.affiliates add column if not exists stripe_connected_account_id text;
alter table public.affiliates add column if not exists stripe_onboarding_complete boolean not null default false;
alter table public.affiliates add column if not exists stripe_details_submitted boolean not null default false;
alter table public.affiliates add column if not exists stripe_charges_enabled boolean not null default false;
alter table public.affiliates add column if not exists stripe_payouts_enabled boolean not null default false;
alter table public.affiliates add column if not exists stripe_onboarding_last_url text;
alter table public.affiliates add column if not exists stripe_onboarding_updated_at timestamptz;

comment on column public.affiliates.stripe_connected_account_id is 'Stripe Connect Express account id (acct_...)';
comment on column public.affiliates.stripe_onboarding_complete is 'True when details submitted and payouts are enabled (see sync job).';
