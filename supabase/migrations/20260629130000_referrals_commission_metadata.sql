-- Enrich affiliate commission ledger with traceable invoice metadata.
-- Existing rows remain valid with NULL in new columns.

alter table public.referrals
  add column if not exists transaction_amount numeric(14, 2),
  add column if not exists commission_rate numeric(5, 2),
  add column if not exists currency text;

comment on column public.referrals.transaction_amount is
  'Invoice amount paid in major currency units (after discounts), before commission.';

comment on column public.referrals.commission_rate is
  'Commission rate as a percentage (e.g. 18.00 for 18%).';

comment on column public.referrals.currency is
  'Stripe invoice currency code (lowercase, e.g. usd).';
