-- Support Rithmic string fill_id and symbol-scoped contract keys (Tradovate ids cast to text).

alter table public.broker_integration_executions
  alter column external_fill_id type text using external_fill_id::text;

alter table public.broker_integration_executions
  alter column external_contract_id type text using external_contract_id::text;

alter table public.broker_integration_account_sync
  alter column max_external_fill_id type text using max_external_fill_id::text;

alter table public.broker_integration_account_sync
  add column if not exists provider_sync_state jsonb not null default '{}'::jsonb;

comment on column public.broker_integration_account_sync.provider_sync_state is
  'Provider-specific incremental sync checkpoints (e.g. Rithmic ssboe index).';
