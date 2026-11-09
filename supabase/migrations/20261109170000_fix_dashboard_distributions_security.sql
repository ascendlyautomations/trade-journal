-- NY session migration replaced analytics_dashboard_distributions_block via CREATE OR REPLACE,
-- which reset SECURITY DEFINER and dropped the auth.uid() owner gate (42501 on trades).

do $mig$
declare
  src text;
  updated text;
begin
  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'analytics_dashboard_distributions_block'
    and pg_get_function_identity_arguments(p.oid) =
      'p_user_id uuid, p_start date, p_end date, p_account_id uuid';

  if src is null then
    raise exception 'analytics_dashboard_distributions_block(uuid, date, date, uuid) was not found';
  end if;

  if position('auth.uid() is not distinct from p_user_id' in src) = 0 then
    if position('where t.user_id = p_user_id' in src) = 0 then
      raise exception 'analytics_dashboard_distributions_block trade owner predicate was not found';
    end if;
    updated := replace(
      src,
      'where t.user_id = p_user_id',
      'where t.user_id = p_user_id and auth.uid() is not distinct from p_user_id'
    );
    execute updated;
  end if;
end
$mig$;

alter function public.analytics_dashboard_distributions_block(uuid, date, date, uuid)
  security definer;

alter function public.analytics_dashboard_distributions_block(uuid, date, date, uuid)
  set search_path = public, pg_temp;

revoke all on function public.analytics_dashboard_distributions_block(uuid, date, date, uuid)
  from public, anon;

grant execute on function public.analytics_dashboard_distributions_block(uuid, date, date, uuid)
  to authenticated;

comment on function public.analytics_dashboard_distributions_block(uuid, date, date, uuid) is
  'Dashboard V3 distributions (sessions, symbols, heatmaps). SECURITY DEFINER with auth.uid() = p_user_id — no direct trades SELECT grant.';
