-- Stripe subscription.cancel_at (scheduled cancellation timestamp), distinct from current_period_end.

alter table public.profiles
  add column if not exists cancel_at timestamptz;

comment on column public.profiles.cancel_at is
  'Stripe subscription.cancel_at — when the subscription is scheduled to end (e.g. trial cancel). Synced from webhooks only.';
