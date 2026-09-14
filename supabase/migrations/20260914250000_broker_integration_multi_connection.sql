-- Allow multiple broker identities per TradeTraxs user (e.g. several Tradovate logins).

alter table public.broker_integration_connections
  drop constraint if exists broker_integration_connections_user_provider_unique;

alter table public.broker_integration_connections
  add column if not exists provider_display_name text,
  add column if not exists connection_label text;

-- One active row per TradeTraxs user + provider + Tradovate user id (when known).
create unique index if not exists broker_integration_connections_active_identity_idx
  on public.broker_integration_connections (user_id, provider, provider_user_id)
  where provider_user_id is not null
    and status in ('connected', 'reconnect_required', 'error');

create index if not exists broker_integration_connections_user_provider_active_idx
  on public.broker_integration_connections (user_id, provider, status, connected_at desc nulls last);

comment on column public.broker_integration_connections.provider_display_name is
  'Safe provider-returned display metadata (not credentials).';

comment on column public.broker_integration_connections.connection_label is
  'Optional user-editable label to distinguish connections in Settings.';

-- OAuth intent: add another connection vs reconnect an existing one (server-side only).
alter table public.integration_oauth_states
  add column if not exists oauth_intent text not null default 'connect_new',
  add column if not exists target_connection_id uuid references public.broker_integration_connections (id) on delete set null;

alter table public.integration_oauth_states
  drop constraint if exists integration_oauth_states_intent_check;

alter table public.integration_oauth_states
  add constraint integration_oauth_states_intent_check check (
    oauth_intent in ('connect_new', 'reconnect')
  );
