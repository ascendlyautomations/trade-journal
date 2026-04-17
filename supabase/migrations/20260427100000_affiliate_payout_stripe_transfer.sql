-- Stripe Connect transfer id after admin marks payout paid.

alter table public.affiliate_payout_requests add column if not exists stripe_transfer_id text;

comment on column public.affiliate_payout_requests.stripe_transfer_id is
  'Stripe Transfer id (tr_...) sent to the affiliate connected account';
