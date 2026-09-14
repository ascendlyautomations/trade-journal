-- Provider account discovery + mapping to TradeTraxs accounts (no OAuth credentials).

create table if not exists public.broker_integration_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  connection_id uuid not null references public.broker_integration_connections (id) on delete cascade,
  provider text not null,
  external_account_id text not null,
  external_account_name text,
  external_display_name text,
  external_metadata jsonb not null default '{}'::jsonb,
  tradetraxs_account_id uuid references public.accounts (id) on delete set null,
  sync_enabled boolean not null default true,
  status text not null default 'discovered',
  discovered_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint broker_integration_accounts_provider_check check (char_length(provider) > 0),
  constraint broker_integration_accounts_external_id_check check (char_length(external_account_id) > 0),
  constraint broker_integration_accounts_status_check check (
    status in ('discovered', 'linked', 'inactive')
  ),
  constraint broker_integration_accounts_connection_provider_external_unique unique (
    connection_id,
    provider,
    external_account_id
  )
);

create index if not exists broker_integration_accounts_user_provider_idx
  on public.broker_integration_accounts (user_id, provider, updated_at desc);

create index if not exists broker_integration_accounts_tradetraxs_account_idx
  on public.broker_integration_accounts (tradetraxs_account_id)
  where tradetraxs_account_id is not null;

comment on table public.broker_integration_accounts is
  'Discovered broker accounts mapped to TradeTraxs accounts. Idempotent on external_account_id per connection.';

alter table public.broker_integration_accounts enable row level security;

create policy broker_integration_accounts_select_own
  on public.broker_integration_accounts
  for select
  to authenticated
  using (user_id = auth.uid());

-- Inserts/updates via BFF service role only.

alter table public.broker_integration_connections
  drop constraint if exists broker_integration_connections_status_check;

alter table public.broker_integration_connections
  add constraint broker_integration_connections_status_check check (
    status in ('connected', 'disconnected', 'error', 'reconnect_required')
  );
