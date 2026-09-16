-- Rithmic V1: persist login username + system metadata only; passwords are transient per operation.

alter table public.broker_integration_connections
  add column if not exists broker_login_username text;

comment on column public.broker_integration_connections.broker_login_username is
  'Non-secret broker login id (e.g. Rithmic username). Passwords are never stored.';

comment on column public.broker_integration_connections.credentials_ciphertext is
  'Encrypted OAuth tokens (Tradovate). Rithmic rows must keep this null (passwords are transient).';

-- After deploy, run scripts/backfill-rithmic-transient-credentials.ts once to migrate legacy
-- Rithmic ciphertext into broker_login_username and clear password material.
