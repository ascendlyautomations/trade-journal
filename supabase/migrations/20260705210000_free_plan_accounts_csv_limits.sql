-- Free plan: up to 3 manual trading accounts; CSV import cooldown tracking.

alter table public.profiles
  add column if not exists last_csv_import_at timestamptz;

comment on column public.profiles.last_csv_import_at is
  'Free tier: timestamp of last successful CSV import; Pro users ignore the weekly limit.';

-- Legacy one-time import flag → start cooldown window from migration time.
update public.profiles
set last_csv_import_at = now()
where coalesce(has_used_csv_import, false) = true
  and last_csv_import_at is null;

create or replace function public.trades_enforce_free_plan_accounts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_pro_user boolean;
  new_key text;
  registration_count int;
  key_registered boolean;
  free_plan_account_limit constant int := 3;
begin
  if coalesce(new.mode, '') = 'backtest' then
    return new;
  end if;

  if lower(trim(coalesce(new.account_type::text, ''))) = 'imported' then
    return new;
  end if;

  is_pro_user := false;
  select coalesce(p.is_pro, false)
    or lower(trim(coalesce(p.subscription_status::text, ''))) in ('active', 'trialing')
  into is_pro_user
  from public.profiles p
  where p.id = new.user_id;

  if not found then
    is_pro_user := false;
  end if;

  if coalesce(is_pro_user, false) then
    return new;
  end if;

  new_key := public.compute_trade_account_key(
    new.account_type::text,
    new.account_size::text,
    new.account_id::text
  );

  select count(*)::int
  into registration_count
  from public.user_accounts ua
  where ua.user_id = new.user_id
    and lower(trim(coalesce(ua.account_type, ''))) <> 'imported';

  select exists (
    select 1
    from public.user_accounts ua
    where ua.user_id = new.user_id
      and ua.account_key = new_key
  )
  into key_registered;

  if coalesce(registration_count, 0) >= free_plan_account_limit
     and not coalesce(key_registered, false) then
    raise exception 'FREE_PLAN_ACCOUNT_LIMIT'
      using hint = 'Free plan allows up to 3 accounts. Upgrade to Pro for unlimited accounts.';
  end if;

  return new;
end;
$$;

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
