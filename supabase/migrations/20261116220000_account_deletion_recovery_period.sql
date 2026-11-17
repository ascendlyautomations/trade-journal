-- 7-day account deletion recovery: schedule, restore, visibility, hourly cron hook (disabled until BFF config is inserted).

alter table public.profiles
  add column if not exists deletion_requested_at timestamptz,
  add column if not exists scheduled_deletion_at timestamptz;

comment on column public.profiles.deletion_requested_at is
  'Set when the owner confirms account deletion; data kept until scheduled_deletion_at.';
comment on column public.profiles.scheduled_deletion_at is
  'UTC timestamp when permanent deletion may run. Null means not pending deletion.';

create index if not exists profiles_scheduled_deletion_at_idx
  on public.profiles (scheduled_deletion_at)
  where scheduled_deletion_at is not null;

revoke select (deletion_requested_at, scheduled_deletion_at) on table public.profiles from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Public discovery visibility (feeds, search, leaderboards, profile reads).
-- ---------------------------------------------------------------------------

create or replace function public.profile_is_eligible_for_public_discovery(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_user_id is not null
    and exists (
      select 1
      from public.profiles p
      where p.id = p_user_id
        and p.scheduled_deletion_at is null
    );
$$;

comment on function public.profile_is_eligible_for_public_discovery(uuid) is
  'False when a profile has a pending or overdue scheduled deletion.';

revoke all on function public.profile_is_eligible_for_public_discovery(uuid) from public;
grant execute on function public.profile_is_eligible_for_public_discovery(uuid) to anon, authenticated;

create or replace function public.profile_is_visible_to_viewer(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_profile_id is not null
    and exists (
      select 1
      from public.profiles p
      where p.id = p_profile_id
        and (
          p.id is not distinct from auth.uid()
          or (
            coalesce(p.is_hidden_from_community, false) = false
            and p.scheduled_deletion_at is null
          )
          or exists (
            select 1
            from public.admin_users au
            where au.user_id = auth.uid()
          )
        )
    );
$$;

comment on function public.profile_is_visible_to_viewer(uuid) is
  'Owner, admin, or discoverable profiles. Pending-deletion profiles hidden from other users.';

-- ---------------------------------------------------------------------------
-- Owner schedule / restore / status (authenticated).
-- ---------------------------------------------------------------------------

create or replace function public.schedule_own_account_deletion()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := timezone('utc', now());
  v_scheduled timestamptz;
  v_req timestamptz;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select p.deletion_requested_at, p.scheduled_deletion_at
  into v_req, v_scheduled
  from public.profiles p
  where p.id = v_uid
  for update;

  if not found then
    raise exception 'Profile not found';
  end if;

  if v_scheduled is not null and v_scheduled > v_now then
    return jsonb_build_object(
      'user_id', v_uid,
      'deletion_requested_at', v_req,
      'scheduled_deletion_at', v_scheduled,
      'already_scheduled', true
    );
  end if;

  v_req := v_now;
  v_scheduled := v_now + interval '7 days';

  update public.profiles
  set
    deletion_requested_at = v_req,
    scheduled_deletion_at = v_scheduled
  where id = v_uid;

  return jsonb_build_object(
    'user_id', v_uid,
    'deletion_requested_at', v_req,
    'scheduled_deletion_at', v_scheduled,
    'already_scheduled', false
  );
end;
$$;

revoke all on function public.schedule_own_account_deletion() from public;
grant execute on function public.schedule_own_account_deletion() to authenticated;

create or replace function public.restore_own_account_from_deletion()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := timezone('utc', now());
  v_scheduled timestamptz;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select p.scheduled_deletion_at
  into v_scheduled
  from public.profiles p
  where p.id = v_uid
  for update;

  if not found or v_scheduled is null then
    return jsonb_build_object('restored', false);
  end if;

  -- Permanent delete cron may be running; still allow restore until row is removed.
  update public.profiles
  set
    deletion_requested_at = null,
    scheduled_deletion_at = null
  where id = v_uid
    and scheduled_deletion_at is not null;

  return jsonb_build_object('restored', true);
end;
$$;

revoke all on function public.restore_own_account_from_deletion() from public;
grant execute on function public.restore_own_account_from_deletion() to authenticated;

create or replace function public.account_deletion_status()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'pending',
        p.scheduled_deletion_at is not null
          and p.deletion_requested_at is not null,
        'deletion_requested_at', p.deletion_requested_at,
        'scheduled_deletion_at', p.scheduled_deletion_at
      )
      from public.profiles p
      where p.id = auth.uid()
    ),
  '{"pending": false, "deletion_requested_at": null, "scheduled_deletion_at": null}'::jsonb
  );
$$;

revoke all on function public.account_deletion_status() from public;
grant execute on function public.account_deletion_status() to authenticated;

-- Protected from self-service profile updates (patch existing trigger body).
do $mig$
declare
  src text;
  updated text;
begin
  select pg_get_functiondef(p.oid)
  into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'profiles_reject_privileged_self_update';

  if src is null then
    raise exception 'profiles_reject_privileged_self_update was not found';
  end if;

  if position('deletion_requested_at' in src) > 0 then
    return;
  end if;

  updated := replace(
    src,
    E'  if new.referred_by is distinct from old.referred_by then',
    E'  if new.deletion_requested_at is distinct from old.deletion_requested_at
     or new.scheduled_deletion_at is distinct from old.scheduled_deletion_at then
    raise exception ''Protected profile fields cannot be modified.'';
  end if;\n\n  if new.referred_by is distinct from old.referred_by then'
  );

  if updated = src then
    raise exception 'profiles_reject_privileged_self_update patch anchor not found';
  end if;

  execute updated;
end;
$mig$;

-- ---------------------------------------------------------------------------
-- Service-role permanent deletion helpers.
-- ---------------------------------------------------------------------------

create or replace function public.list_account_deletions_due_for_permanent_delete(p_limit integer default 25)
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.id
  from public.profiles p
  where p.scheduled_deletion_at is not null
    and p.scheduled_deletion_at <= timezone('utc', now())
  order by p.scheduled_deletion_at asc
  limit greatest(1, least(coalesce(p_limit, 25), 100));
$$;

revoke all on function public.list_account_deletions_due_for_permanent_delete(integer) from public;
grant execute on function public.list_account_deletions_due_for_permanent_delete(integer) to service_role;

create or replace function public.account_deletion_still_due(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_user_id
      and p.scheduled_deletion_at is not null
      and p.scheduled_deletion_at <= timezone('utc', now())
  );
$$;

revoke all on function public.account_deletion_still_due(uuid) from public;
grant execute on function public.account_deletion_still_due(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- pg_cron → BFF (disabled until private.scheduled_account_deletion_config row exists).
-- ---------------------------------------------------------------------------

create schema if not exists private;

create table if not exists private.scheduled_account_deletion_config (
  id smallint primary key check (id = 1),
  bff_url text not null,
  bearer_secret text not null,
  enabled boolean not null default false,
  updated_at timestamptz not null default timezone('utc', now())
);

comment on table private.scheduled_account_deletion_config is
  'Insert after deploy with CRON_SECRET-matching bearer. Set enabled=true only after end-to-end tests pass.';

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to postgres, service_role;
revoke all on table private.scheduled_account_deletion_config from public, anon, authenticated;
grant select on table private.scheduled_account_deletion_config to postgres, service_role;

create or replace function private.scheduled_account_deletion_http_dispatch()
returns bigint
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_url text;
  v_secret text;
  v_enabled boolean;
  v_request_id bigint;
begin
  select c.bff_url, c.bearer_secret, c.enabled
  into v_url, v_secret, v_enabled
  from private.scheduled_account_deletion_config c
  where c.id = 1;

  if coalesce(v_enabled, false) is not true
    or v_url is null
    or v_secret is null
    or length(trim(v_url)) = 0
    or length(trim(v_secret)) = 0
  then
    return null;
  end if;

  select net.http_get(
    url := trim(v_url),
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || trim(v_secret)
    ),
    timeout_milliseconds := 120000
  )
  into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function private.scheduled_account_deletion_http_dispatch() from public, anon, authenticated;

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema extensions;

do $$
declare
  v_jobid bigint;
begin
  select jobid into v_jobid
  from cron.job
  where jobname = 'scheduled-account-deletion-hourly';

  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
  end if;

  perform cron.schedule(
    'scheduled-account-deletion-hourly',
    '15 * * * *',
    $cron$select private.scheduled_account_deletion_http_dispatch();$cron$
  );
end;
$$;