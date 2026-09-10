-- Idempotent App Store Server Notifications V2 processing (Phase 7).

create table if not exists public.apple_subscription_notifications (
  id uuid primary key default gen_random_uuid(),
  notification_uuid text not null,
  original_transaction_id text null,
  notification_type text not null,
  subtype text null,
  environment text null check (
    environment is null or environment in ('Sandbox', 'Production')
  ),
  signed_date timestamptz null,
  processed_at timestamptz not null default now(),
  constraint apple_subscription_notifications_uuid_key unique (notification_uuid)
);

create index if not exists apple_subscription_notifications_original_tx_idx
  on public.apple_subscription_notifications (original_transaction_id);

comment on table public.apple_subscription_notifications is
  'Processed App Store Server Notifications V2 payloads — deduplicates Apple retries.';

alter table public.apple_subscription_notifications enable row level security;

-- Service role only (BFF). No authenticated client access.
