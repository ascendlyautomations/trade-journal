-- Protect billing interval fields from client self-updates (synced via Stripe webhooks).
create or replace function public.profiles_reject_privileged_self_update()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_is_beta_referral_grant boolean;
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

  v_is_beta_referral_grant :=
    upper(trim(coalesce(new.referred_by, ''))) = 'TRAXBETA10302'
    and upper(trim(coalesce(old.referred_by, '')))
      is distinct from upper(trim(coalesce(new.referred_by, '')));

  if new.is_pro is distinct from old.is_pro
     and not v_is_beta_referral_grant then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.is_beta_tester is distinct from old.is_beta_tester
     and not v_is_beta_referral_grant then
    raise exception 'Protected profile fields cannot be modified.';
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
