-- Broker OAuth connections (Tradovate first). Credential blobs are server-only (service role + app encryption).

create table if not exists public.broker_integration_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  provider text not null,
  status text not null default 'disconnected',
  provider_user_id text,
  credentials_ciphertext text,
  access_token_expires_at timestamptz,
  refresh_token_expires_at timestamptz,
  api_environment text,
  connected_at timestamptz,
  disconnected_at timestamptz,
  last_sync_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint broker_integration_connections_user_provider_unique unique (user_id, provider),
  constraint broker_integration_connections_provider_check check (char_length(provider) > 0),
  constraint broker_integration_connections_status_check check (
    status in ('connected', 'disconnected', 'error')
  ),
  constraint broker_integration_connections_api_environment_check check (
    api_environment is null or api_environment in ('demo', 'live')
  )
);

create index if not exists broker_integration_connections_user_status_idx
  on public.broker_integration_connections (user_id, provider, status);

comment on table public.broker_integration_connections is
  'OAuth broker connections. credentials_ciphertext is encrypted application-side; no client access.';

alter table public.broker_integration_connections enable row level security;

-- No policies: authenticated clients must not read/write token material. BFF uses service role.
