-- Phase 5: automatic Tradovate sync state (listener runs in separate long-lived worker).

alter table public.broker_integration_account_sync
  add column if not exists auto_sync_enabled boolean not null default true,
  add column if not exists last_event_at timestamptz,
  add column if not exists last_auto_sync_at timestamptz,
  add column if not exists sync_dirty_at timestamptz,
  add column if not exists pending_sync_after_current boolean not null default false;

comment on column public.broker_integration_account_sync.auto_sync_enabled is
  'When true, broker-sync worker may auto-reconcile this mapping after Tradovate user events.';

alter table public.broker_integration_connections
  add column if not exists listener_status text not null default 'stopped',
  add column if not exists listener_last_connected_at timestamptz,
  add column if not exists listener_last_disconnected_at timestamptz,
  add column if not exists listener_reconnect_count integer not null default 0,
  add column if not exists listener_last_error_code text,
  add column if not exists listener_last_error_message text;

alter table public.broker_integration_connections
  drop constraint if exists broker_integration_connections_listener_status_check;

alter table public.broker_integration_connections
  add constraint broker_integration_connections_listener_status_check check (
    listener_status in ('stopped', 'connecting', 'connected', 'reconnect_required', 'error')
  );

comment on column public.broker_integration_connections.listener_status is
  'Updated by tradovate-sync worker; web app remains stateless.';
