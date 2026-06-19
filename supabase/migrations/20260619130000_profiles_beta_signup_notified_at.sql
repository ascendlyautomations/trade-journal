-- Idempotency guard for beta signup admin email notifications.

alter table public.profiles
  add column if not exists beta_signup_notified_at timestamptz;

comment on column public.profiles.beta_signup_notified_at is
  'Set once when admin is notified of a new beta referral signup (TRAXBETA10302).';
