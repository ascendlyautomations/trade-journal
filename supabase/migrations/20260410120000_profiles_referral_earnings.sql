-- Stripe promo → affiliate: commission stored separately from referral_revenue (legacy affiliates flow).
alter table public.profiles
  add column if not exists referral_earnings numeric default 0;

comment on column public.profiles.referral_earnings is
  'Cumulative commission from Stripe promotion codes matched to referral_code (e.g. 18% of amount paid).';
