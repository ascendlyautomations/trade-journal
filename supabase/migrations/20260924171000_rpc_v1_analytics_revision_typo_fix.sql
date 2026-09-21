-- Fix Phase 6E typo: v.updated_at → v_updated_at in rpc_v1_analytics_revision.

create or replace function public.rpc_v1_analytics_revision()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_revision bigint;
  v_updated_at timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select u.revision, u.updated_at
  into v_revision, v_updated_at
  from public.user_analytics_state u
  where u.user_id = v_uid;

  if not found then
    v_revision := 0;
    v_updated_at := now();
  end if;

  return jsonb_build_object(
    'revision', v_revision,
    'updated_at', to_char(v_updated_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  );
end;
$$;

revoke all on function public.rpc_v1_analytics_revision() from public;
revoke all on function public.rpc_v1_analytics_revision() from anon;
grant execute on function public.rpc_v1_analytics_revision() to authenticated;
