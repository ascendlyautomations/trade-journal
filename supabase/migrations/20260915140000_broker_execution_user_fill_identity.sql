-- Broker executions dedupe by durable user + provider + Fill.id (not ephemeral connection_id).
-- Survives disconnect/reconnect and broker account remapping without duplicate imports.

with ranked as (
  select
    id,
    row_number() over (
      partition by user_id, provider, external_fill_id
      order by
        (canonical_trade_id is not null) desc,
        created_at asc,
        id asc
    ) as rn
  from public.broker_integration_executions
)
delete from public.broker_integration_executions e
using ranked r
where e.id = r.id
  and r.rn > 1;

alter table public.broker_integration_executions
  drop constraint if exists broker_integration_executions_provider_fill_unique;

create unique index if not exists broker_integration_executions_user_provider_fill_unique
  on public.broker_integration_executions (user_id, provider, external_fill_id);

comment on index public.broker_integration_executions_user_provider_fill_unique is
  'One ledger row per authenticated user per provider Fill.id — survives connection/mapping churn.';
