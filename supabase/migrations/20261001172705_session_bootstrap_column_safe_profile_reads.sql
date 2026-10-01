-- rpc_v1_session_bootstrap is SECURITY INVOKER and passed the whole profiles
-- row into _v1_session_is_pro(profiles) and
-- _v1_session_early_access_active(profiles). After table SELECT was replaced
-- with a public-column grant, constructing that composite raises 42501
-- permission denied for table profiles. The helpers only read granted
-- columns, so pass those columns instead of the row.
--
-- Stays SECURITY INVOKER. No caller-supplied user id. No table SELECT grant.
-- RLS stays enabled. stripe_customer_id stays behind profile_owner_private_fields().

create or replace function public._v1_session_early_access_active(
  p_status text,
  p_enrolled_at timestamptz,
  p_started_at timestamptz,
  p_campaign_id text,
  p_enrollment_source text,
  p_ends_at timestamptz
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select
    p_status = 'active'
    and p_enrolled_at is not null
    and p_started_at is not null
    and p_campaign_id = 'traxs_pro_for_life_v1'
    and p_enrollment_source in ('standard_email', 'standard_oauth')
    and p_ends_at is not null
    and p_ends_at > now();
$$;

create or replace function public._v1_session_is_pro(
  p_is_pro boolean,
  p_creator_access boolean,
  p_subscription_status text,
  p_trial_end timestamp,
  p_early_access_status text,
  p_early_access_enrolled_at timestamptz,
  p_early_access_started_at timestamptz,
  p_early_access_campaign_id text,
  p_early_access_enrollment_source text,
  p_early_access_ends_at timestamptz
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select
    coalesce(p_is_pro, false)
    or coalesce(p_creator_access, false)
    or lower(trim(coalesce(p_subscription_status, ''))) in ('active', 'trialing')
    or public._v1_session_early_access_active(
      p_early_access_status,
      p_early_access_enrolled_at,
      p_early_access_started_at,
      p_early_access_campaign_id,
      p_early_access_enrollment_source,
      p_early_access_ends_at
    )
    or (
      p_trial_end is not null
      and p_trial_end > now()
    );
$$;

revoke all on function public._v1_session_early_access_active(
  text, timestamptz, timestamptz, text, text, timestamptz
) from public, anon;

grant execute on function public._v1_session_early_access_active(
  text, timestamptz, timestamptz, text, text, timestamptz
) to authenticated;

revoke all on function public._v1_session_is_pro(
  boolean, boolean, text, timestamp, text, timestamptz, timestamptz, text, text, timestamptz
) from public, anon;

grant execute on function public._v1_session_is_pro(
  boolean, boolean, text, timestamp, text, timestamptz, timestamptz, text, text, timestamptz
) to authenticated;

do $mig$
declare
  src text;
  updated text;
begin
  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_session_bootstrap'
    and pg_get_function_identity_arguments(p.oid) = '';

  if src is null then
    raise exception 'rpc_v1_session_bootstrap() was not found';
  end if;

  if position('security definer' in lower(src)) > 0 then
    raise exception 'rpc_v1_session_bootstrap must stay security invoker';
  end if;

  if position('public._v1_session_is_pro(p)' in src) = 0
     and position('public._v1_session_is_pro(p.is_pro' in src) > 0
     and position('public._v1_session_early_access_active(p.early_access_status' in src) > 0 then
    return;
  end if;

  if position('public._v1_session_is_pro(p)' in src) = 0
     or position('public._v1_session_early_access_active(p)' in src) = 0 then
    raise exception 'rpc_v1_session_bootstrap whole-row profile helper call was not found';
  end if;

  updated := replace(
    src,
    'public._v1_session_early_access_active(p)',
    'public._v1_session_early_access_active(p.early_access_status, p.early_access_enrolled_at, p.early_access_started_at, p.early_access_campaign_id, p.early_access_enrollment_source, p.early_access_ends_at)'
  );
  updated := replace(
    updated,
    'public._v1_session_is_pro(p)',
    'public._v1_session_is_pro(p.is_pro, p.creator_access, p.subscription_status, p.trial_end, p.early_access_status, p.early_access_enrolled_at, p.early_access_started_at, p.early_access_campaign_id, p.early_access_enrollment_source, p.early_access_ends_at)'
  );

  if position('public._v1_session_is_pro(p)' in updated) > 0
     or position('public._v1_session_early_access_active(p)' in updated) > 0 then
    raise exception 'rpc_v1_session_bootstrap whole-row profile helper call remains';
  end if;

  if position('security definer' in lower(updated)) > 0 then
    raise exception 'rpc_v1_session_bootstrap must stay security invoker';
  end if;

  execute updated;
end
$mig$;
