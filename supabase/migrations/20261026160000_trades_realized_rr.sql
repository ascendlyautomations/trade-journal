-- Realized R:R (distinct from targeted `rr`). Nullable for broker/legacy rows.
alter table public.trades
  add column if not exists realized_rr numeric;

comment on column public.trades.realized_rr is
  'Realized R multiple for the closed trade; targeted plan lives in rr.';
