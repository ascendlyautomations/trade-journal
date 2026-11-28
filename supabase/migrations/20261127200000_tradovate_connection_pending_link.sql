-- Future broker↔TradeTraxs link intent when OAuth succeeds before Tradovate exposes account rows.
alter table public.broker_integration_connections
  add column if not exists pending_tradetraxs_account_id uuid references public.accounts (id) on delete set null;

create index if not exists broker_integration_connections_pending_tradetraxs_idx
  on public.broker_integration_connections (user_id, pending_tradetraxs_account_id)
  where pending_tradetraxs_account_id is not null;

comment on column public.broker_integration_connections.pending_tradetraxs_account_id is
  'Reserved TradeTraxs trading account for the next discovered broker mapping on this connection; not a broker_integration_accounts row.';