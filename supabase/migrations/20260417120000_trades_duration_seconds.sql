-- Optional hold duration for trades (CSV import + UI).
alter table public.trades
  add column if not exists duration_seconds integer;

comment on column public.trades.duration_seconds is 'Trade hold duration in whole seconds; null if unknown.';
