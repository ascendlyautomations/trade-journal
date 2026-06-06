alter table public.profiles
  add column if not exists trader_type text;

comment on column public.profiles.trader_type is
  'Trader category: Futures, Options, or Investor.';
