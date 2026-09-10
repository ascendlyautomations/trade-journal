-- TraxPro Apple App Store subscriptions (additive; Stripe fields on profiles unchanged).
-- Unified Pro access: profile_is_pro_user OR active apple_subscriptions row.

create table if not exists public.apple_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  original_transaction_id text not null,
  latest_transaction_id text not null,
  product_id text not null,
  environment text not null check (environment in ('Sandbox', 'Production')),
  billing_interval text null check (
    billing_interval is null
    or billing_interval in ('monthly', 'six_month', 'yearly')
  ),
  status text not null default 'active' check (
    status in ('active', 'expired', 'revoked', 'grace_period', 'billing_retry')
  ),
  expires_at timestamptz null,
  revoked_at timestamptz null,
  purchased_at timestamptz null,
  last_verified_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint apple_subscriptions_original_transaction_id_key unique (original_transaction_id)
);

create index if not exists apple_subscriptions_user_id_idx
  on public.apple_subscriptions (user_id);

create index if not exists apple_subscriptions_active_expires_idx
  on public.apple_subscriptions (user_id, expires_at)
  where status in ('active', 'grace_period', 'billing_retry');

comment on table public.apple_subscriptions is
  'Verified App Store TraxPro subscription state synced from StoreKit via BFF.';

comment on column public.apple_subscriptions.original_transaction_id is
  'Apple subscription group original transaction id — idempotent sync key.';

alter table public.apple_subscriptions enable row level security;

drop policy if exists apple_subscriptions_select_own on public.apple_subscriptions;
create policy apple_subscriptions_select_own
  on public.apple_subscriptions
  for select
  to authenticated
  using (user_id = auth.uid());

-- Writes only via service role (BFF). No authenticated insert/update/delete policies.

create or replace function public.apple_subscription_is_active(p_row public.apple_subscriptions)
returns boolean
language sql
immutable
as $$
  select p_row.status in ('active', 'grace_period', 'billing_retry')
    and p_row.revoked_at is null
    and (
      p_row.expires_at is null
      or p_row.expires_at > now()
    );
$$;

comment on function public.apple_subscription_is_active(public.apple_subscriptions) is
  'True when a verified Apple subscription row grants TraxPro access.';

create or replace function public.profile_has_active_apple_subscription(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.apple_subscriptions a
    where a.user_id = p_user_id
      and public.apple_subscription_is_active(a)
  );
$$;

comment on function public.profile_has_active_apple_subscription(uuid) is
  'True when the user has a verified, unexpired Apple TraxPro subscription.';

-- Extend unified DB Pro check (Stripe / manual / creator / early access unchanged).
create or replace function public.profile_is_pro_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(p.is_pro, false)
    or coalesce(p.creator_access, false)
    or lower(trim(coalesce(p.subscription_status::text, ''))) in ('active', 'trialing')
    or (p.trial_end is not null and p.trial_end > now())
    or (
      p.early_access_status = 'active'
      and p.early_access_campaign_id = 'traxs_pro_for_life_v1'
      and p.early_access_enrollment_source in ('standard_email', 'standard_oauth')
      and p.early_access_enrolled_at is not null
      and p.early_access_started_at is not null
      and p.early_access_ends_at is not null
      and p.early_access_ends_at > now()
    )
    or public.profile_has_active_apple_subscription(p_user_id)
  from public.profiles p
  where p.id = p_user_id;
$$;

comment on function public.profile_is_pro_user(uuid) is
  'True for Stripe/manual/creator/early-access Pro OR active verified Apple subscription.';
