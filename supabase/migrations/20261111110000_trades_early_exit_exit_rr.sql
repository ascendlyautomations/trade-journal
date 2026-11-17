-- Manual journal: early exit attestation + optional manual exit R:R when prices cannot derive it.
alter table public.trades
  add column if not exists early_exit boolean not null default false;

alter table public.trades
  add column if not exists exit_rr numeric;

comment on column public.trades.early_exit is
  'Manual Add/Edit: winner closed before full take-profit; max_rr_reached is peak favorability, not exit.';

comment on column public.trades.exit_rr is
  'Manual early-exit winners: realized R:R at exit when entry/exit prices cannot derive it.';
