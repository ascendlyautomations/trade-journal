-- Affiliate ledger: store Stripe Price ID for analytics (not used in commission math).
-- Clarify transaction_amount = subscription revenue after discounts, before taxes.

alter table public.referrals
  add column if not exists stripe_price_id text;

comment on column public.referrals.stripe_price_id is
  'Stripe Price ID from the invoice line item (analytics only; not used for commission).';

comment on column public.referrals.transaction_amount is
  'Subscription revenue in major currency units after discounts and before taxes (commission base).';
