-- Align broker_integration_account_sync.last_sync_status with Tradovate sync engine
-- (IMPORT_SUCCESS_PARTIAL → last_sync_status = 'partial').

alter table public.broker_integration_account_sync
  drop constraint if exists broker_integration_account_sync_status_check;

alter table public.broker_integration_account_sync
  add constraint broker_integration_account_sync_status_check check (
    last_sync_status in (
      'never',
      'syncing',
      'success',
      'partial',
      'error',
      'reconnect_required'
    )
  );

comment on constraint broker_integration_account_sync_status_check on public.broker_integration_account_sync is
  'Persisted sync lifecycle; partial = import completed with incomplete fill acquisition (see last_sync_error_code import_partial).';
