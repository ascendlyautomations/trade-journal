-- Rithmic Phase 3: track last successful credential verification per connection.

alter table public.broker_integration_connections
  add column if not exists last_verified_at timestamptz;

comment on column public.broker_integration_connections.last_verified_at is
  'Last time broker credentials were verified successfully (connect/reconnect).';
