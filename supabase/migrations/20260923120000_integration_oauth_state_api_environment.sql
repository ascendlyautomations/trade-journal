alter table public.integration_oauth_states
  add column if not exists api_environment text;

alter table public.integration_oauth_states
  drop constraint if exists integration_oauth_states_api_environment_check;

alter table public.integration_oauth_states
  add constraint integration_oauth_states_api_environment_check check (
    api_environment is null or api_environment in ('demo', 'live')
  );

comment on column public.integration_oauth_states.api_environment is
  'Tradovate demo/live OAuth+REST environment bound to this authorization attempt.';
