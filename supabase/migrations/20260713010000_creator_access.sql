-- Complimentary Pro for select creators via /creator?code=XXXX.
-- Manage codes in public.creator_access_codes (Supabase Table Editor or SQL).
-- Default: single-use (max_redemptions = 1). Raise max_redemptions for multi-use.
-- Revoke unused/future use: set is_active = false.

alter table public.profiles
  add column if not exists creator_access boolean not null default false;

alter table public.profiles
  add column if not exists creator_code text;

alter table public.profiles
  add column if not exists creator_granted_at timestamptz;

comment on column public.profiles.creator_access is
  'Complimentary Pro via creator invite code. No Stripe subscription.';
comment on column public.profiles.creator_code is
  'Creator access code that granted complimentary Pro.';
comment on column public.profiles.creator_granted_at is
  'When complimentary creator Pro was granted.';

create table if not exists public.creator_access_codes (
  code text primary key,
  label text,
  is_active boolean not null default true,
  max_redemptions integer not null default 1
    check (max_redemptions >= 1),
  expires_at timestamptz,
  notes text,
  created_at timestamptz not null default now()
);

comment on table public.creator_access_codes is
  'Invite codes for complimentary Pro. Insert/update here — no app deploy needed.';

create table if not exists public.creator_code_redemptions (
  id uuid primary key default gen_random_uuid(),
  code text not null references public.creator_access_codes (code) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  unique (code, user_id)
);

create index if not exists creator_code_redemptions_user_id_idx
  on public.creator_code_redemptions (user_id);

create index if not exists creator_code_redemptions_code_idx
  on public.creator_code_redemptions (code);

alter table public.creator_access_codes enable row level security;
alter table public.creator_code_redemptions enable row level security;

-- No client policies: service role / security definer only.

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
  from public.profiles p
  where p.id = p_user_id;
$$;

comment on function public.profile_is_pro_user(uuid) is
  'True when is_pro, creator_access, active/trialing subscription, or future trial_end.';

create or replace function public.profiles_reject_privileged_self_update()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if exists (
    select 1
    from public.admin_users au
    where au.user_id = auth.uid()
  ) then
    return new;
  end if;

  if auth.uid() is null or auth.uid() <> old.id then
    return new;
  end if;

  if new.referred_by is distinct from old.referred_by then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.is_pro is distinct from old.is_pro then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.creator_access is distinct from old.creator_access then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.creator_code is distinct from old.creator_code then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.creator_granted_at is distinct from old.creator_granted_at then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.is_beta_tester is distinct from old.is_beta_tester then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.use_free_tier is distinct from old.use_free_tier then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.trial_end is distinct from old.trial_end then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.has_used_csv_import is distinct from old.has_used_csv_import then
    if coalesce(old.has_used_csv_import, false) = true then
      raise exception 'Protected profile fields cannot be modified.';
    end if;
    if coalesce(new.has_used_csv_import, false) = false then
      raise exception 'Protected profile fields cannot be modified.';
    end if;
  end if;

  if new.last_csv_import_at is distinct from old.last_csv_import_at then
    if old.last_csv_import_at is not null
       and (
         new.last_csv_import_at is null
         or new.last_csv_import_at <= old.last_csv_import_at
       ) then
      raise exception 'Protected profile fields cannot be modified.';
    end if;
  end if;

  if new.subscription_status is distinct from old.subscription_status then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.stripe_customer_id is distinct from old.stripe_customer_id then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.stripe_price_id is distinct from old.stripe_price_id then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.billing_interval is distinct from old.billing_interval then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.cancel_at_period_end is distinct from old.cancel_at_period_end then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.cancel_at is distinct from old.cancel_at then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.current_period_end is distinct from old.current_period_end then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.referral_earnings is distinct from old.referral_earnings then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.referral_count is distinct from old.referral_count then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.is_banned is distinct from old.is_banned then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.banned_by is distinct from old.banned_by then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.banned_at is distinct from old.banned_at then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.banned_reason is distinct from old.banned_reason then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  return new;
end;
$$;

-- Atomic redeem (service_role only). Grants complimentary Pro + records redemption.
create or replace function public.redeem_creator_access_code(
  p_code text,
  p_user_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized text := upper(trim(coalesce(p_code, '')));
  invite public.creator_access_codes%rowtype;
  used_count int;
  granted_at timestamptz := now();
begin
  if not public.rate_limit_is_service_role() then
    raise exception 'FORBIDDEN';
  end if;

  if p_user_id is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if normalized = '' then
    return 'invalid';
  end if;

  if exists (
    select 1 from public.profiles p
    where p.id = p_user_id and coalesce(p.creator_access, false) = true
  ) then
    return 'already';
  end if;

  select * into invite
  from public.creator_access_codes c
  where c.code = normalized
  for update;

  if not found
     or invite.is_active is not true
     or (invite.expires_at is not null and invite.expires_at <= now()) then
    return 'invalid';
  end if;

  select count(*)::int into used_count
  from public.creator_code_redemptions r
  where r.code = normalized;

  if coalesce(used_count, 0) >= invite.max_redemptions then
    return 'invalid';
  end if;

  update public.profiles
  set
    creator_access = true,
    creator_code = normalized,
    creator_granted_at = granted_at,
    is_pro = true
  where id = p_user_id;

  insert into public.creator_code_redemptions (code, user_id, redeemed_at)
  values (normalized, p_user_id, granted_at)
  on conflict (code, user_id) do nothing;

  update public.accounts
  set can_add_trades = true
  where user_id = p_user_id;

  return 'ok';
end;
$$;

revoke all on function public.redeem_creator_access_code(text, uuid) from public;
grant execute on function public.redeem_creator_access_code(text, uuid) to service_role;

comment on function public.redeem_creator_access_code(text, uuid) is
  'Service-role redeem of a creator invite code. Returns ok | already | invalid.';
