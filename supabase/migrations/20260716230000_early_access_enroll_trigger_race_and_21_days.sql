-- Fix Early Access enrollment when an auth trigger creates the profile shell
-- before the client can stamp signup_flow_source / referral_code.
-- Also switches complimentary Early Access from 14 days to 21 days.

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
