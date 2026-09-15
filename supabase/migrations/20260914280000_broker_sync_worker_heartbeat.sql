-- Worker liveness (updated by tradovate-sync-worker; web UI uses staleness to detect offline worker).

alter table public.broker_integration_connections
  add column if not exists listener_worker_heartbeat_at timestamptz;

comment on column public.broker_integration_connections.listener_worker_heartbeat_at is
  'Set periodically by tradovate-sync-worker while managing this connection; stale = worker not running.';
