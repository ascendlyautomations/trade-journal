-- Revert 7-day account deletion recovery (20261116220000). Immediate delete only via BFF.
-- Fails if any profile still has a scheduled deletion pending — clear those manually first.

do $guard$
begin
  if exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'profiles'
      and c.column_name = 'scheduled_deletion_at'
  ) and exists (
    select 1
    from public.profiles p
    where p.scheduled_deletion_at is not null
  ) then
    raise exception
      'revert_account_deletion_recovery: % profile(s) still have scheduled_deletion_at. Restore or permanently delete them before applying this migration.',
      (select count(*)::int from public.profiles where scheduled_deletion_at is not null);
  end if;
end;
$guard$;

do $cron$
declare
  v_jobid bigint;
begin
  select jobid into v_jobid
  from cron.job
  where jobname = 'scheduled-account-deletion-hourly';

  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
  end if;
end;
$cron$;

drop function if exists private.scheduled_account_deletion_http_dispatch();
drop table if exists private.scheduled_account_deletion_config;

drop function if exists public.account_deletion_still_due(uuid);
drop function if exists public.list_account_deletions_due_for_permanent_delete(integer);
drop function if exists public.account_deletion_status();
drop function if exists public.restore_own_account_from_deletion();
drop function if exists public.schedule_own_account_deletion();
drop function if exists public.profile_is_eligible_for_public_discovery(uuid);

drop index if exists public.profiles_scheduled_deletion_at_idx;

alter table public.profiles
  drop column if exists deletion_requested_at,
  drop column if exists scheduled_deletion_at;

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
          or coalesce(p.is_hidden_from_community, false) = false
          or exists (
            select 1
            from public.admin_users au
            where au.user_id = auth.uid()
          )
        )
    );
$$;

comment on function public.profile_is_visible_to_viewer(uuid) is
  'True for the profile owner, a platform admin, or any profile that is not hidden from the community.';

-- Remove self-update guards for deleted recovery columns (patch only when present).
do $trig$
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
    return;
  end if;

  if position('deletion_requested_at' in src) = 0 then
    return;
  end if;

  updated := replace(
    src,
    E'  if new.deletion_requested_at is distinct from old.deletion_requested_at
     or new.scheduled_deletion_at is distinct from old.scheduled_deletion_at then
    raise exception ''Protected profile fields cannot be modified.'';
  end if;\n\n  if new.referred_by is distinct from old.referred_by then',
    E'  if new.referred_by is distinct from old.referred_by then'
  );

  if updated = src then
    raise exception 'profiles_reject_privileged_self_update recovery guard removal failed';
  end if;

  execute updated;
end;
$trig$;