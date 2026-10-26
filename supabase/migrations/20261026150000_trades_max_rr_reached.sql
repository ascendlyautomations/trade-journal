-- Optional journal metric: highest R:R reached before a losing/breakeven trade closed.
-- Separate from realized `rr`; never backfilled or inferred from P&L.

alter table public.trades
  add column if not exists max_rr_reached numeric;

comment on column public.trades.max_rr_reached is
  'Owner-entered highest reward-to-risk reached before close (optional; typically on losses).';
