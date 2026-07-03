-- Users who chose "Continue with Free Account" at signup skip Stripe checkout.
alter table public.profiles
  add column if not exists use_free_tier boolean not null default false;

comment on column public.profiles.use_free_tier is
  'True when the user explicitly signed up for the free tier and opted out of the TraxPro trial checkout gate.';
