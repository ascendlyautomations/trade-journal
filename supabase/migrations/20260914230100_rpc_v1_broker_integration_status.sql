-- Safe broker integration metadata for authenticated clients (no OAuth tokens).

create or replace function public.rpc_v1_broker_integration_status(
  p_provider text default 'tradovate'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_provider text := lower(trim(coalesce(p_provider, '')));
  v_row public.broker_integration_connections%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if v_provider = '' then
    raise exception 'invalid_provider' using errcode = '22023';
  end if;

  select *
  into v_row
  from public.broker_integration_connections c
  where c.user_id = v_uid
    and c.provider = v_provider
  limit 1;

  if not found then
    return jsonb_build_object(
      'provider', v_provider,
      'connected', false,
      'status', 'disconnected',
      'connected_at', null,
      'last_sync_at', null,
      'provider_user_id', null,
      'api_environment', null
    );
  end if;

  return jsonb_build_object(
    'provider', v_row.provider,
    'connected', v_row.status = 'connected',
    'status', v_row.status,
    'connected_at', v_row.connected_at,
    'last_sync_at', v_row.last_sync_at,
    'provider_user_id',
      case when v_row.status = 'connected' then v_row.provider_user_id else null end,
    'api_environment',
      case
        when v_row.status = 'connected' and v_row.api_environment in ('demo', 'live')
        then v_row.api_environment
        else null
      end
  );
end;
$$;

comment on function public.rpc_v1_broker_integration_status(text) is
  'Returns non-sensitive broker integration metadata for the signed-in user.';

revoke all on function public.rpc_v1_broker_integration_status(text) from public;
grant execute on function public.rpc_v1_broker_integration_status(text) to authenticated;
