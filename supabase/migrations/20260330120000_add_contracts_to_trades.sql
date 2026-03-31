-- Optional: run in Supabase SQL editor if migrations are not applied automatically.
alter table public.trades
  add column if not exists contracts integer null;

comment on column public.trades.contracts is 'Number of contracts / lots for the trade';
