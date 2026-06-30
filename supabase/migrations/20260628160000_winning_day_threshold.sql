-- Optional minimum daily net P/L for a day to count as a winning day (prop firm rules).
alter table public.accounts
  add column if not exists winning_day_threshold numeric;

comment on column public.accounts.winning_day_threshold is
  'Minimum daily net P/L ($) for a futures trading day to count toward winning_days. Null = any positive day counts.';
