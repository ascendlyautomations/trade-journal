-- User-configurable max drawdown limit (dollars from equity peak), optional.
alter table public.profiles
  add column if not exists max_drawdown_limit numeric;

comment on column public.profiles.max_drawdown_limit is
  'Optional dollar cap on drawdown from peak; used on dashboard risk display.';
