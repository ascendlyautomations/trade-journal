-- Remote iOS monetization controls. Production starts with both flags false.
--
-- Change later without an iOS binary:
--   update public.app_monetization_settings
--      set ios_paywall_enabled = true,
--          entitlement_enforcement_enabled = false,
--          updated_at = now()
--    where id = 1;
--
-- App Review account (paywall on, enforcement inherits global):
--   insert into public.app_monetization_account_overrides (user_id, ios_paywall_enabled, note)
--   values ('<review-user-uuid>', true, 'App Review')
--   on conflict (user_id) do update
--     set ios_paywall_enabled = excluded.ios_paywall_enabled,
--         note = excluded.note,
--         updated_at = now();
--
-- Optional grandfather, left OFF until you choose a cutoff:
--   update public.app_monetization_settings
--      set launch_access_mode = 'created_before_cutoff',
--          launch_access_cutoff_at = '2026-01-01T00:00:00Z',
--          updated_at = now()
--    where id = 1;

create table if not exists public.app_monetization_settings (
  id integer primary key check (id = 1),
  ios_paywall_enabled boolean not null default false,
  entitlement_enforcement_enabled boolean not null default false,
  launch_access_mode text not null default 'none'
    check (launch_access_mode in ('none', 'created_before_cutoff')),
  launch_access_cutoff_at timestamptz null,
  updated_at timestamptz not null default now()
);

insert into public.app_monetization_settings (id)
values (1)
on conflict (id) do nothing;

comment on table public.app_monetization_settings is
  'Singleton remote monetization config. Both flags default false. Missing row must be treated as false.';

comment on column public.app_monetization_settings.ios_paywall_enabled is
  'When true, iOS may show the TraxPro plan screen and start StoreKit purchases.';

comment on column public.app_monetization_settings.entitlement_enforcement_enabled is
  'When true, Free-plan usage limits apply to users who are not Pro. When false, those limits are not applied.';

comment on column public.app_monetization_settings.launch_access_mode is
  'none, or created_before_cutoff. Default none so no grandfather policy is active.';

create table if not exists public.app_monetization_account_overrides (
  user_id uuid primary key references auth.users (id) on delete cascade,
  ios_paywall_enabled boolean null,
  entitlement_enforcement_enabled boolean null,
  note text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.app_monetization_account_overrides is
  'Per-account flag overrides. Null inherits the global row. Used for App Review access.';

alter table public.app_monetization_settings enable row level security;
alter table public.app_monetization_account_overrides enable row level security;

revoke all on table public.app_monetization_settings from anon, authenticated;
revoke all on table public.app_monetization_account_overrides from anon, authenticated;

grant select on table public.app_monetization_settings to authenticated;

drop policy if exists app_monetization_settings_select_authenticated
  on public.app_monetization_settings;
create policy app_monetization_settings_select_authenticated
  on public.app_monetization_settings
  for select
  to authenticated
  using (true);

-- Overrides are service-role only. No authenticated policies.

create or replace function public.free_plan_limits_enforced()
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
    (
      select s.entitlement_enforcement_enabled
      from public.app_monetization_settings s
      where s.id = 1
    ),
    false
  );
$$;

comment on function public.free_plan_limits_enforced() is
  'True only when the global entitlement_enforcement_enabled flag is on. Missing config is false.';

create or replace function public.launch_access_grant_applies(p_user_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
    from public.app_monetization_settings s
    join public.profiles p on p.id = p_user_id
    where s.id = 1
      and s.launch_access_mode = 'created_before_cutoff'
      and s.launch_access_cutoff_at is not null
      and p.created_at is not null
      and p.created_at < s.launch_access_cutoff_at
  );
$$;

comment on function public.launch_access_grant_applies(uuid) is
  'True when the stored grandfather policy includes this profile. Default policy matches nobody.';

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
    or public.launch_access_grant_applies(p_user_id)
  from public.profiles p
  where p.id = p_user_id;
$$;

comment on function public.profile_is_pro_user(uuid) is
  'True for Stripe, manual, creator, early-access, Apple, or an explicitly enabled launch-access grant.';

-- Free-plan caps. Abuse rate limits in the DM trigger stay in place.

create or replace function public.reels_enforce_free_plan_daily_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  free_plan_daily_clip_limit constant integer := 3;
  clip_count integer;
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if not public.free_plan_limits_enforced() then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  clip_count := public.free_plan_count_clips_today(new.user_id);

  if coalesce(clip_count, 0) >= free_plan_daily_clip_limit then
    raise exception 'FREE_PLAN_DAILY_CLIP_LIMIT'
      using hint = 'You''ve reached the Free plan limit of 3 clips every 24 hours.';
  end if;

  return new;
end;
$$;

create or replace function public.trades_enforce_free_plan_daily_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  free_plan_daily_trade_limit constant integer := 3;
  trade_count integer;
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if not public.free_plan_limits_enforced() then
    return new;
  end if;

  if coalesce(new.mode, '') = 'backtest' then
    return new;
  end if;

  if lower(trim(coalesce(new.account_type::text, ''))) = 'imported' then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  trade_count := public.free_plan_count_trades_today(new.user_id);

  if coalesce(trade_count, 0) >= free_plan_daily_trade_limit then
    raise exception 'FREE_PLAN_DAILY_TRADE_LIMIT'
      using hint = 'You''ve reached the Free plan limit of 3 trades every 24 hours.';
  end if;

  return new;
end;
$$;

create or replace function public.posts_enforce_free_plan_daily_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  free_plan_daily_post_limit constant integer := 3;
  post_count integer;
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if not public.free_plan_limits_enforced() then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  if new.trade_id is not null
     and exists (
       select 1
       from public.posts p
       where p.trade_id = new.trade_id
     ) then
    return new;
  end if;

  post_count := public.free_plan_count_posts_today(new.user_id);

  if coalesce(post_count, 0) >= free_plan_daily_post_limit then
    raise exception 'FREE_PLAN_DAILY_POST_LIMIT'
      using hint = 'You''ve reached the Free plan limit of 3 posts every 24 hours.';
  end if;

  return new;
end;
$$;

create or replace function public.profile_posts_enforce_free_plan_daily_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  free_plan_daily_post_limit constant integer := 3;
  post_count integer;
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if not public.free_plan_limits_enforced() then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  post_count := public.free_plan_count_posts_today(new.user_id);

  if coalesce(post_count, 0) >= free_plan_daily_post_limit then
    raise exception 'FREE_PLAN_DAILY_POST_LIMIT'
      using hint = 'You''ve reached the Free plan limit of 3 posts every 24 hours.';
  end if;

  return new;
end;
$$;

create or replace function public.accounts_enforce_free_plan_create_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  entry_enabled_count int;
begin
  if not public.free_plan_limits_enforced() then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  if new.can_add_trades is not true then
    return new;
  end if;

  select count(*)::int into entry_enabled_count
  from public.accounts
  where user_id = new.user_id
    and can_add_trades = true;

  if coalesce(entry_enabled_count, 0) >= 3 then
    raise exception 'FREE_PLAN_ACCOUNT_LIMIT'
      using hint = 'Free plan allows up to 3 active accounts. Upgrade to Pro for unlimited accounts.';
  end if;

  return new;
end;
$$;

create or replace function public.trades_enforce_free_plan_accounts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  entry_enabled_count int;
  account_allows boolean;
begin
  if coalesce(new.mode, '') = 'backtest' then
    return new;
  end if;

  if lower(trim(coalesce(new.account_type::text, ''))) = 'imported' then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  if new.account_id is not null and trim(new.account_id::text) <> '' then
    select a.can_add_trades
    into account_allows
    from public.accounts a
    where a.id::text = nullif(trim(new.account_id::text), '')
      and a.user_id = new.user_id;

    if found then
      if account_allows is not true then
        raise exception 'ACCOUNT_READ_ONLY';
      end if;
      return new;
    end if;
  end if;

  if not public.free_plan_limits_enforced() then
    return new;
  end if;

  select count(*)::int into entry_enabled_count
  from public.accounts
  where user_id = new.user_id
    and can_add_trades = true;

  if coalesce(entry_enabled_count, 0) >= 3 then
    raise exception 'FREE_PLAN_ACCOUNT_LIMIT'
      using hint = 'Free plan allows up to 3 active accounts. Upgrade to Pro for unlimited accounts.';
  end if;

  return new;
end;
$$;

create or replace function public.rate_limit_messages_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  free_plan_daily_dm_limit constant integer := 25;
  dm_count integer;
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if coalesce(new.is_system, false) then
    return new;
  end if;

  if new.conversation_id is not null and new.sender_id is null then
    return new;
  end if;

  if new.sender_id is null then
    return new;
  end if;

  -- Abuse limits apply to every plan. They are not the Free-plan entitlement switch.
  perform public.rate_limit_hit('message_send');

  if new.conversation_id is not null
     and public.free_plan_limits_enforced()
     and not public.profile_is_pro_user(new.sender_id) then
    perform pg_advisory_xact_lock(
      872341,
      hashtext(new.sender_id::text || ':free_plan_dm')
    );
    dm_count := public.free_plan_count_direct_messages_rolling_24h(new.sender_id);
    if coalesce(dm_count, 0) >= free_plan_daily_dm_limit then
      raise exception 'FREE_PLAN_DAILY_DM_LIMIT'
        using hint = 'You''ve reached the Free plan limit of 25 direct messages every 24 hours.';
    end if;
  end if;

  return new;
end;
$$;
