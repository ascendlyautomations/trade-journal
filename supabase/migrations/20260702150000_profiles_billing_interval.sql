-- Track TraxPro billing cadence chosen at checkout / synced from Stripe.
alter table public.profiles
  add column if not exists billing_interval text,
  add column if not exists stripe_price_id text;

comment on column public.profiles.billing_interval is
  'TraxPro billing cadence: monthly, six_month, or yearly.';

comment on column public.profiles.stripe_price_id is
  'Active Stripe Price ID for the TraxPro subscription when known.';
