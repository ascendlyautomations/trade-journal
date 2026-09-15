-- Rithmic Test broker connections (Phase 1+). Tradovate demo/live unchanged.

alter table public.broker_integration_connections
  drop constraint if exists broker_integration_connections_api_environment_check;

alter table public.broker_integration_connections
  add constraint broker_integration_connections_api_environment_check check (
    api_environment is null or api_environment in ('demo', 'live', 'test')
  );

comment on column public.broker_integration_connections.api_environment is
  'Tradovate: demo|live. Rithmic: test (Rithmic Test only until production is explicitly enabled).';
