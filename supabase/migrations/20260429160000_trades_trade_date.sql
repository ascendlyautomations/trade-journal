-- Calendar-selected trade date (YYYY-MM-DD), distinct from legacy `date` / entry_time usage.
alter table public.trades
  add column if not exists trade_date date;
