alter table public.trades
add column if not exists mode text default 'live';

alter table public.trades
add column if not exists strategy text;
