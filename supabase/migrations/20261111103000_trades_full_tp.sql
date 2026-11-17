-- Manual journal: user attests the trade closed at full take-profit (winners only).
alter table public.trades
  add column if not exists full_tp boolean not null default false;

comment on column public.trades.full_tp is
  'Manual Add/Edit: when true and trade is a winner, persisted realized_rr may equal targeted rr.';
