-- Early Access complimentary Pro + race-safe Traxs Pro For Life challenge.
-- This is deliberately separate from profile onboarding and Getting Started.

alter table public.profiles
  add column if not exists early_access_enrolled_at timestamptz,
  add column if not exists early_access_started_at timestamptz,
  add column if not exists early_access_ends_at timestamptz,
  add column if not exists early_access_status text,
  add column if not exists early_access_campaign_id text,
  add column if not exists early_access_enrollment_source text,
  add column if not exists signup_flow_source text,
  add column if not exists lifetime_access_source text,
  add column if not exists lifetime_access_granted_at timestamptz;

alter table public.profiles
  drop constraint if exists profiles_early_access_status_check;
alter table public.profiles
  add constraint profiles_early_access_status_check
  check (
    early_access_status is null
    or early_access_status in (
      'active',
      'expired',
      'converted_lifetime',
      'ineligible'
    )
  );

alter table public.profiles
  drop constraint if exists profiles_early_access_enrollment_source_check;
alter table public.profiles
  add constraint profiles_early_access_enrollment_source_check
  check (
    early_access_enrollment_source is null
    or early_access_enrollment_source in ('standard_email', 'standard_oauth')
  );

alter table public.profiles
  drop constraint if exists profiles_signup_flow_source_check;
alter table public.profiles
  add constraint profiles_signup_flow_source_check
  check (
    signup_flow_source is null
    or signup_flow_source in ('standard_email', 'standard_oauth', 'creator')
  );

comment on column public.profiles.early_access_status is
  'Separate Early Access lifecycle. Never represents a Stripe trial or subscription.';
comment on column public.profiles.lifetime_access_source is
  'Auditable permanent-Pro source. traxs_pro_for_life_v1 is awarded only by the secure claim RPC.';

alter table public.trades
  add column if not exists first_published_at timestamptz;

comment on column public.trades.first_published_at is
  'Server-authored timestamp when the trade first became public; immutable after first publication.';

create or replace function public.trades_set_first_published_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    -- Never accept a client-selected qualifying timestamp.
    if coalesce(new.is_public, false) then
      new.first_published_at := now();
    else
      new.first_published_at := null;
    end if;
    return new;
  end if;

  -- Once recorded, publication time cannot be changed or manufactured again.
  new.first_published_at := old.first_published_at;
  if old.first_published_at is null
     and coalesce(old.is_public, false) = false
     and coalesce(new.is_public, false) = true then
    new.first_published_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trades_set_first_published_at_trigger on public.trades;
create trigger trades_set_first_published_at_trigger
  before insert or update on public.trades
  for each row
  execute function public.trades_set_first_published_at();

create index if not exists trades_early_access_public_days_idx
  on public.trades (user_id, first_published_at)
  where is_public = true and first_published_at is not null;

create table if not exists public.early_access_campaigns (
  campaign_key text not null,
  environment text not null,
  enrollment_enabled boolean not null default true,
  eligibility_starts_at timestamptz not null default now(),
  award_limit integer not null check (award_limit > 0),
  challenge_version integer not null default 1 check (challenge_version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint early_access_campaigns_pkey
    primary key (campaign_key, environment),
  constraint early_access_campaigns_environment_check
    check (environment in ('production', 'preview', 'development'))
);

alter table public.early_access_campaigns
  add column if not exists eligibility_starts_at timestamptz not null default now();

insert into public.early_access_campaigns (
  campaign_key,
  environment,
  enrollment_enabled,
  award_limit,
  challenge_version
)
values
  ('traxs_pro_for_life_v1', 'production', true, 100, 1),
  ('traxs_pro_for_life_v1', 'preview', true, 110, 1),
  ('traxs_pro_for_life_v1', 'development', true, 110, 1)
on conflict (campaign_key, environment) do nothing;

alter table public.early_access_campaigns enable row level security;
revoke all on table public.early_access_campaigns from anon, authenticated;

create table if not exists public.pro_for_life_awards (
  user_id uuid primary key references public.profiles (id) on delete restrict,
  awarded_at timestamptz not null default now(),
  award_type text not null default 'traxs_pro_for_life',
  challenge_version integer not null,
  campaign_key text not null,
  environment text not null,
  referral_user_id uuid references public.profiles (id) on delete set null,
  follow_count integer not null,
  public_trade_day_count integer not null,
  referral_count integer not null,
  constraint pro_for_life_awards_environment_check
    check (environment in ('production', 'preview', 'development')),
  constraint pro_for_life_awards_campaign_environment_fkey
    foreign key (campaign_key, environment)
    references public.early_access_campaigns (campaign_key, environment)
);

create index if not exists pro_for_life_awards_campaign_cap_idx
  on public.pro_for_life_awards (campaign_key, environment, awarded_at);

alter table public.pro_for_life_awards enable row level security;

drop policy if exists "pro_for_life_awards_select_own"
  on public.pro_for_life_awards;
create policy "pro_for_life_awards_select_own"
  on public.pro_for_life_awards
  for select
  to authenticated
  using (user_id = auth.uid());

revoke all on table public.pro_for_life_awards from anon, authenticated;
grant select on table public.pro_for_life_awards to authenticated;

create or replace function public.early_access_environment_valid(p_environment text)
returns boolean
language sql
immutable
as $$
  select p_environment in ('production', 'preview', 'development');
$$;

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
  from public.profiles p
  where p.id = p_user_id;
$$;

comment on function public.profile_is_pro_user(uuid) is
  'True for permanent/admin Pro, creator access, paid/Stripe trial access, or unexpired active Early Access.';

-- Protect Early Access and lifetime markers from authenticated self-updates.
create or replace function public.profiles_protect_early_access_fields()
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
    select 1 from public.admin_users au where au.user_id = auth.uid()
  ) then
    return new;
  end if;

  if auth.uid() = old.id and (
    new.early_access_enrolled_at is distinct from old.early_access_enrolled_at
    or new.early_access_started_at is distinct from old.early_access_started_at
    or new.early_access_ends_at is distinct from old.early_access_ends_at
    or new.early_access_status is distinct from old.early_access_status
    or new.early_access_campaign_id is distinct from old.early_access_campaign_id
    or new.early_access_enrollment_source is distinct from old.early_access_enrollment_source
    or new.signup_flow_source is distinct from old.signup_flow_source
    or new.lifetime_access_source is distinct from old.lifetime_access_source
    or new.lifetime_access_granted_at is distinct from old.lifetime_access_granted_at
  ) then
    raise exception 'Protected Early Access fields cannot be modified.';
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_protect_early_access_fields_trigger
  on public.profiles;
create trigger profiles_protect_early_access_fields_trigger
  before update on public.profiles
  for each row
  execute function public.profiles_protect_early_access_fields();

-- Stripe/service updates may change billing mirrors, but may never revoke an
-- independently awarded lifetime entitlement.
create or replace function public.profiles_preserve_lifetime_pro()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if old.lifetime_access_source = 'traxs_pro_for_life_v1' then
    new.is_pro := true;
    new.lifetime_access_source := old.lifetime_access_source;
    new.lifetime_access_granted_at := old.lifetime_access_granted_at;
    new.early_access_status := 'converted_lifetime';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_preserve_lifetime_pro_trigger
  on public.profiles;
create trigger profiles_preserve_lifetime_pro_trigger
  before update on public.profiles
  for each row
  execute function public.profiles_preserve_lifetime_pro();

drop function if exists public.enroll_early_access(uuid, text);

create or replace function public.enroll_early_access(
  p_user_id uuid,
  p_environment text,
  p_enrollment_source text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  campaign public.early_access_campaigns%rowtype;
  profile_row public.profiles%rowtype;
  enrolled_at timestamptz := clock_timestamp();
begin
  if not public.rate_limit_is_service_role() then
    raise exception 'FORBIDDEN';
  end if;
  if p_user_id is null
     or not public.early_access_environment_valid(p_environment)
     or p_enrollment_source not in ('standard_email', 'standard_oauth') then
    return 'ineligible';
  end if;

  select * into campaign
  from public.early_access_campaigns c
  where c.campaign_key = 'traxs_pro_for_life_v1'
    and c.environment = p_environment;

  if not found or campaign.enrollment_enabled is not true then
    return 'disabled';
  end if;

  select * into profile_row
  from public.profiles p
  where p.id = p_user_id
  for update;

  if not found then
    return 'ineligible';
  end if;

  if profile_row.early_access_enrolled_at is not null
     or profile_row.early_access_started_at is not null
     or profile_row.early_access_ends_at is not null
     or profile_row.early_access_status is not null
     or profile_row.early_access_campaign_id is not null
     or profile_row.early_access_enrollment_source is not null then
    if profile_row.early_access_enrolled_at is not null
       and profile_row.early_access_started_at is not null
       and profile_row.early_access_ends_at is not null
       and profile_row.early_access_campaign_id = campaign.campaign_key
       and profile_row.early_access_enrollment_source in ('standard_email', 'standard_oauth')
       and profile_row.early_access_status in ('active', 'expired', 'converted_lifetime') then
      return 'already_enrolled';
    end if;
    return 'ineligible';
  end if;

  -- Defense in depth: enrollment is only for a profile just created by the
  -- standard signup path. Existing free users cannot be enrolled retroactively.
  -- Auth triggers may create the shell before the client can set
  -- signup_flow_source; null is accepted and stamped during enrollment.
  if profile_row.created_at is null
     or profile_row.created_at < campaign.eligibility_starts_at
     or profile_row.created_at < enrolled_at - interval '15 minutes'
     or (
       profile_row.signup_flow_source is not null
       and profile_row.signup_flow_source is distinct from p_enrollment_source
     )
     or coalesce(profile_row.is_pro, false)
     or coalesce(profile_row.creator_access, false)
     or coalesce(profile_row.is_beta_tester, false)
     or coalesce(profile_row.use_free_tier, false)
     or profile_row.stripe_customer_id is not null
     or lower(trim(coalesce(profile_row.subscription_status::text, '')))
        in ('active', 'trialing')
     or profile_row.trial_end is not null
     or profile_row.lifetime_access_source is not null then
    return 'ineligible';
  end if;

  update public.profiles
  set
    early_access_enrolled_at = enrolled_at,
    early_access_started_at = enrolled_at,
    early_access_ends_at = enrolled_at + interval '21 days',
    early_access_status = 'active',
    early_access_campaign_id = campaign.campaign_key,
    early_access_enrollment_source = p_enrollment_source,
    signup_flow_source = coalesce(
      profile_row.signup_flow_source,
      p_enrollment_source
    ),
    referral_code = coalesce(
      nullif(trim(profile_row.referral_code), ''),
      upper(substr(md5(random()::text || clock_timestamp()::text || p_user_id::text), 1, 6))
    )
  where id = p_user_id;

  return 'enrolled';
end;
$$;

revoke all on function public.enroll_early_access(uuid, text, text) from public;
grant execute on function public.enroll_early_access(uuid, text, text) to service_role;

create or replace function public.expire_early_access(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  changed integer;
begin
  if not public.rate_limit_is_service_role() then
    raise exception 'FORBIDDEN';
  end if;

  update public.profiles
  set early_access_status = 'expired'
  where id = p_user_id
    and early_access_status = 'active'
    and early_access_ends_at <= now()
    and lifetime_access_source is null;

  get diagnostics changed = row_count;
  return changed > 0;
end;
$$;

revoke all on function public.expire_early_access(uuid) from public;
grant execute on function public.expire_early_access(uuid) to service_role;

create or replace function public.expire_early_access_batch()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  changed integer;
begin
  if not public.rate_limit_is_service_role() then
    raise exception 'FORBIDDEN';
  end if;

  update public.profiles
  set early_access_status = 'expired'
  where early_access_status = 'active'
    and early_access_ends_at <= now()
    and lifetime_access_source is null;

  get diagnostics changed = row_count;
  return changed;
end;
$$;

revoke all on function public.expire_early_access_batch() from public;
grant execute on function public.expire_early_access_batch() to service_role;

create or replace function public.get_early_access_progress(
  p_user_id uuid,
  p_environment text
)
returns table (
  status text,
  enrolled_at timestamptz,
  ends_at timestamptz,
  follow_count integer,
  public_trade_day_count integer,
  referral_count integer,
  referral_user_id uuid,
  completed_count integer,
  all_complete boolean,
  award_limit integer,
  awards_claimed integer,
  spots_remaining integer,
  already_awarded boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  p public.profiles%rowtype;
  cap integer;
  follows integer;
  trade_days integer;
  referrals integer;
  referred_user uuid;
  referral_code_owners integer;
  claimed integer;
  awarded boolean;
begin
  if not public.rate_limit_is_service_role() then
    raise exception 'FORBIDDEN';
  end if;
  if not public.early_access_environment_valid(p_environment) then
    raise exception 'INVALID_ENVIRONMENT';
  end if;

  select * into p from public.profiles where id = p_user_id;
  if not found then
    return;
  end if;
  if p.early_access_campaign_id is distinct from 'traxs_pro_for_life_v1'
     or p.early_access_enrollment_source is null
     or p.early_access_enrollment_source not in ('standard_email', 'standard_oauth')
     or p.early_access_enrolled_at is null
     or p.early_access_started_at is null
     or p.early_access_ends_at is null
     or p.early_access_status is null
     or p.early_access_status not in ('active', 'expired', 'converted_lifetime') then
    return;
  end if;

  select c.award_limit into cap
  from public.early_access_campaigns c
  where c.campaign_key = 'traxs_pro_for_life_v1'
    and c.environment = p_environment;

  select count(distinct f.following_id)::integer into follows
  from public.followers f
  where f.follower_id = p_user_id
    and f.following_id <> p_user_id;

  select count(distinct (
    timezone('America/New_York', t.first_published_at)::date
  ))::integer into trade_days
  from public.trades t
  where t.user_id = p_user_id
    and t.is_public = true
    and t.first_published_at is not null;

  select count(*)::integer into referral_code_owners
  from public.profiles owner
  where upper(trim(coalesce(owner.referral_code, ''))) =
        upper(trim(coalesce(p.referral_code, '')))
    and trim(coalesce(p.referral_code, '')) <> '';

  if referral_code_owners = 1 then
    select count(*)::integer
    into referrals
    from public.profiles r
    where r.id <> p_user_id
      and r.created_at is not null
      and upper(trim(coalesce(r.referred_by, ''))) =
          upper(trim(coalesce(p.referral_code, '')))
      and trim(coalesce(p.referral_code, '')) <> '';

    select r.id into referred_user
    from public.profiles r
    where r.id <> p_user_id
      and r.created_at is not null
      and upper(trim(coalesce(r.referred_by, ''))) =
          upper(trim(coalesce(p.referral_code, '')))
      and trim(coalesce(p.referral_code, '')) <> ''
    order by r.created_at asc, r.id asc
    limit 1;
  else
    referrals := 0;
    referred_user := null;
  end if;

  select count(*)::integer into claimed
  from public.pro_for_life_awards a
  where a.campaign_key = 'traxs_pro_for_life_v1'
    and a.environment = p_environment;

  select exists (
    select 1 from public.pro_for_life_awards a where a.user_id = p_user_id
  ) into awarded;

  return query
  select
    case
      when p.early_access_status = 'active'
           and p.early_access_ends_at <= now() then 'expired'
      else p.early_access_status
    end,
    p.early_access_enrolled_at,
    p.early_access_ends_at,
    least(coalesce(follows, 0), 3),
    least(coalesce(trade_days, 0), 3),
    least(coalesce(referrals, 0), 1),
    referred_user,
    (case when follows >= 3 then 1 else 0 end)
      + (case when trade_days >= 3 then 1 else 0 end)
      + (case when referrals >= 1 then 1 else 0 end),
    follows >= 3 and trade_days >= 3 and referrals >= 1,
    coalesce(cap, 0),
    coalesce(claimed, 0),
    greatest(coalesce(cap, 0) - coalesce(claimed, 0), 0),
    awarded;
end;
$$;

revoke all on function public.get_early_access_progress(uuid, text) from public;
grant execute on function public.get_early_access_progress(uuid, text) to service_role;

create or replace function public.claim_pro_for_life(
  p_user_id uuid,
  p_environment text
)
returns table (
  result text,
  awarded_at timestamptz,
  follow_count integer,
  public_trade_day_count integer,
  referral_count integer,
  spots_remaining integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.profiles%rowtype;
  campaign public.early_access_campaigns%rowtype;
  follows integer;
  trade_days integer;
  referrals integer;
  referred_user uuid;
  referral_code_owners integer;
  claimed integer;
  grant_time timestamptz := clock_timestamp();
begin
  if not public.rate_limit_is_service_role() then
    raise exception 'FORBIDDEN';
  end if;
  if p_user_id is null or not public.early_access_environment_valid(p_environment) then
    return query select 'ineligible', null::timestamptz, 0, 0, 0, 0;
    return;
  end if;

  -- Serialize every final claim for this campaign/environment.
  perform pg_advisory_xact_lock(
    hashtextextended('traxs_pro_for_life_v1:' || p_environment, 0)
  );

  select * into campaign
  from public.early_access_campaigns c
  where c.campaign_key = 'traxs_pro_for_life_v1'
    and c.environment = p_environment
  for update;

  if not found then
    return query select 'ineligible', null::timestamptz, 0, 0, 0, 0;
    return;
  end if;

  if exists (
    select 1 from public.pro_for_life_awards a where a.user_id = p_user_id
  ) then
    select a.awarded_at into grant_time
    from public.pro_for_life_awards a where a.user_id = p_user_id;
    select count(*)::integer into claimed
    from public.pro_for_life_awards a
    where a.campaign_key = campaign.campaign_key
      and a.environment = campaign.environment;
    return query
      select 'already_awarded', grant_time, 3, 3, 1,
        greatest(campaign.award_limit - claimed, 0);
    return;
  end if;

  select * into p
  from public.profiles
  where id = p_user_id
  for update;

  if not found
     or p.early_access_status is null
     or p.early_access_status not in ('active', 'converted_lifetime')
     or p.early_access_campaign_id is distinct from campaign.campaign_key
     or p.early_access_enrollment_source is null
     or p.early_access_enrollment_source not in ('standard_email', 'standard_oauth')
     or p.early_access_enrolled_at is null
     or p.early_access_started_at is null
     or p.early_access_ends_at is null then
    return query select 'ineligible', null::timestamptz, 0, 0, 0, 0;
    return;
  end if;

  if p.early_access_status = 'active' and p.early_access_ends_at <= grant_time then
    update public.profiles
    set early_access_status = 'expired'
    where id = p_user_id;
    return query select 'expired', null::timestamptz, 0, 0, 0, 0;
    return;
  end if;

  if coalesce(p.creator_access, false)
     or coalesce(p.is_beta_tester, false)
     or lower(trim(coalesce(p.subscription_status::text, '')))
        in ('active', 'trialing')
     or (p.trial_end is not null and p.trial_end > grant_time)
     or (
       p.is_pro = true
       and coalesce(p.lifetime_access_source, '') <> 'traxs_pro_for_life_v1'
     ) then
    return query select 'ineligible', null::timestamptz, 0, 0, 0, 0;
    return;
  end if;

  select count(distinct f.following_id)::integer into follows
  from public.followers f
  where f.follower_id = p_user_id
    and f.following_id <> p_user_id;

  select count(distinct (
    timezone('America/New_York', t.first_published_at)::date
  ))::integer into trade_days
  from public.trades t
  where t.user_id = p_user_id
    and t.is_public = true
    and t.first_published_at is not null;

  select count(*)::integer into referral_code_owners
  from public.profiles owner
  where upper(trim(coalesce(owner.referral_code, ''))) =
        upper(trim(coalesce(p.referral_code, '')))
    and trim(coalesce(p.referral_code, '')) <> '';

  if referral_code_owners = 1 then
    select count(*)::integer
    into referrals
    from public.profiles r
    where r.id <> p_user_id
      and r.created_at is not null
      and upper(trim(coalesce(r.referred_by, ''))) =
          upper(trim(coalesce(p.referral_code, '')))
      and trim(coalesce(p.referral_code, '')) <> '';

    select r.id into referred_user
    from public.profiles r
    where r.id <> p_user_id
      and r.created_at is not null
      and upper(trim(coalesce(r.referred_by, ''))) =
          upper(trim(coalesce(p.referral_code, '')))
      and trim(coalesce(p.referral_code, '')) <> ''
    order by r.created_at asc, r.id asc
    limit 1;
  else
    referrals := 0;
    referred_user := null;
  end if;

  if coalesce(follows, 0) < 3
     or coalesce(trade_days, 0) < 3
     or coalesce(referrals, 0) < 1 then
    return query
      select 'incomplete', null::timestamptz,
        least(coalesce(follows, 0), 3),
        least(coalesce(trade_days, 0), 3),
        least(coalesce(referrals, 0), 1),
        0;
    return;
  end if;

  select count(*)::integer into claimed
  from public.pro_for_life_awards a
  where a.campaign_key = campaign.campaign_key
    and a.environment = campaign.environment;

  if claimed >= campaign.award_limit then
    return query
      select 'sold_out', null::timestamptz,
        least(follows, 3), least(trade_days, 3), least(referrals, 1), 0;
    return;
  end if;

  insert into public.pro_for_life_awards (
    user_id,
    awarded_at,
    award_type,
    challenge_version,
    campaign_key,
    environment,
    referral_user_id,
    follow_count,
    public_trade_day_count,
    referral_count
  )
  values (
    p_user_id,
    grant_time,
    'traxs_pro_for_life',
    campaign.challenge_version,
    campaign.campaign_key,
    campaign.environment,
    referred_user,
    follows,
    trade_days,
    referrals
  );

  update public.profiles
  set
    is_pro = true,
    lifetime_access_source = 'traxs_pro_for_life_v1',
    lifetime_access_granted_at = grant_time,
    early_access_status = 'converted_lifetime'
  where id = p_user_id;

  return query
    select 'awarded', grant_time,
      least(follows, 3),
      least(trade_days, 3),
      least(referrals, 1),
      greatest(campaign.award_limit - claimed - 1, 0);
end;
$$;

revoke all on function public.claim_pro_for_life(uuid, text) from public;
grant execute on function public.claim_pro_for_life(uuid, text) to service_role;
