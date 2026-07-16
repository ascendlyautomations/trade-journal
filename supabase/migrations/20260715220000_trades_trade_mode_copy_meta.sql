-- Trade Mode + Copy Traded metadata (source / destination accounts).
-- Multiplier is derived from copied_account_ids length — not stored separately.

alter table public.trades
  add column if not exists trade_mode text;

alter table public.trades
  add column if not exists source_account_id uuid
  references public.accounts (id) on delete set null;

alter table public.trades
  add column if not exists copied_account_ids uuid[] not null default '{}'::uuid[];

comment on column public.trades.trade_mode is
  'Journal trade mode: live | sim | replay | backtest | copy_traded';

comment on column public.trades.source_account_id is
  'Copy Traded: account where the trade originated';

comment on column public.trades.copied_account_ids is
  'Copy Traded: destination account ids (badge ×N = array length)';

create index if not exists trades_source_account_id_idx
  on public.trades (source_account_id)
  where source_account_id is not null;

create index if not exists trades_trade_mode_idx
  on public.trades (trade_mode)
  where trade_mode is not null;
