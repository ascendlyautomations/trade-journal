-- Broker-imported trades: journal enrichment lifecycle (distinct from CSV is_initial_import + reviewed).

alter table public.trades
  add column if not exists broker_enrichment_status text;

alter table public.trades
  drop constraint if exists trades_broker_enrichment_status_check;

alter table public.trades
  add constraint trades_broker_enrichment_status_check check (
    broker_enrichment_status is null
    or broker_enrichment_status in ('pending', 'completed', 'dismissed')
  );

comment on column public.trades.broker_enrichment_status is
  'Tradovate (and future broker) imports: pending until user completes/skips/dismisses journal enrichment.';

create index if not exists trades_broker_enrichment_pending_idx
  on public.trades (user_id, created_at asc)
  where import_source = 'tradovate'
    and broker_enrichment_status = 'pending';
