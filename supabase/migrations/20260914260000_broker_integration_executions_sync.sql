-- Tradovate Phase 4: durable fill ledger, per-account sync state, canonical trade provenance.

create table if not exists public.broker_integration_executions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  connection_id uuid not null references public.broker_integration_connections (id) on delete cascade,
  broker_integration_account_id uuid not null references public.broker_integration_accounts (id) on delete cascade,
  provider text not null default 'tradovate',
  external_fill_id bigint not null,
  external_order_id bigint,
  external_contract_id bigint not null,
  contract_name text,
  symbol_root text,
  side text not null,
  quantity integer not null check (quantity > 0),
  price numeric not null,
  executed_at timestamptz not null,
  provider_metadata jsonb not null default '{}'::jsonb,
  lifecycle_key text,
  canonical_trade_id uuid references public.trades (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint broker_integration_executions_provider_check check (char_length(provider) > 0),
  constraint broker_integration_executions_side_check check (side in ('Buy', 'Sell')),
  constraint broker_integration_executions_provider_fill_unique unique (
    provider,
    connection_id,
    external_fill_id
  )
);

create index if not exists broker_integration_executions_account_executed_idx
  on public.broker_integration_executions (
    broker_integration_account_id,
    external_contract_id,
    executed_at asc,
    external_fill_id asc
  );

create index if not exists broker_integration_executions_lifecycle_idx
  on public.broker_integration_executions (broker_integration_account_id, lifecycle_key)
  where lifecycle_key is not null;

comment on table public.broker_integration_executions is
  'Provider fills/executions for idempotent broker sync and trade reconstruction.';

create table if not exists public.broker_integration_account_sync (
  broker_integration_account_id uuid primary key references public.broker_integration_accounts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  connection_id uuid not null references public.broker_integration_connections (id) on delete cascade,
  last_sync_attempt_at timestamptz,
  last_sync_success_at timestamptz,
  last_sync_status text not null default 'never',
  last_sync_error_code text,
  last_sync_error_message text,
  max_external_fill_id bigint,
  max_executed_at timestamptz,
  sync_lock_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint broker_integration_account_sync_status_check check (
    last_sync_status in ('never', 'syncing', 'success', 'error', 'reconnect_required')
  )
);

create index if not exists broker_integration_account_sync_user_idx
  on public.broker_integration_account_sync (user_id, connection_id);

comment on table public.broker_integration_account_sync is
  'Manual sync checkpoints and locks per linked broker account mapping.';

alter table public.trades
  add column if not exists broker_connection_id uuid references public.broker_integration_connections (id) on delete set null,
  add column if not exists broker_integration_account_id uuid references public.broker_integration_accounts (id) on delete set null,
  add column if not exists broker_lifecycle_id text,
  add column if not exists last_broker_sync_at timestamptz;

comment on column public.trades.broker_lifecycle_id is
  'Stable reconstructed lifecycle id (e.g. tradovate:v1:{mapping}:{contract}:{seq}).';

create unique index if not exists trades_user_broker_lifecycle_unique
  on public.trades (user_id, broker_lifecycle_id)
  where broker_lifecycle_id is not null;

alter table public.broker_integration_executions enable row level security;
alter table public.broker_integration_account_sync enable row level security;

create policy broker_integration_executions_select_own
  on public.broker_integration_executions
  for select
  to authenticated
  using (user_id = auth.uid());

create policy broker_integration_account_sync_select_own
  on public.broker_integration_account_sync
  for select
  to authenticated
  using (user_id = auth.uid());
