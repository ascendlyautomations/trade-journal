-- Durable broadcaster disconnect grace (Vercel-safe): schedule in Postgres, process via BFF + pg_cron.

alter table public.room_live_broadcasts
  add column if not exists broadcaster_disconnect_check_at timestamptz;

alter table public.room_live_broadcasts
  add column if not exists broadcaster_disconnect_reason text;

comment on column public.room_live_broadcasts.broadcaster_disconnect_check_at is
  'When set and <= now(), BFF may end the broadcast if the broadcaster is still absent from LiveKit (grace after disconnect webhooks).';

create index if not exists room_live_broadcasts_disconnect_check_due_idx
  on public.room_live_broadcasts (broadcaster_disconnect_check_at)
  where ended_at is null and broadcaster_disconnect_check_at is not null;

create or replace function private.livekit_broadcast_disconnect_http_dispatch(p_body jsonb)
returns bigint
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_base_url text;
  v_secret text;
  v_url text;
  v_request_id bigint;
begin
  select c.bff_process_url, c.bearer_secret
  into v_base_url, v_secret
  from private.livekit_outbox_processor_config c
  where c.id = 1;

  if v_base_url is null or v_secret is null or length(trim(v_base_url)) = 0 then
    return null;
  end if;

  v_url := regexp_replace(trim(v_base_url), '/process-outbox/?$', '/process-broadcast-disconnect');

  select net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_secret
    ),
    body := coalesce(p_body, '{}'::jsonb)
  )
  into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function private.livekit_broadcast_disconnect_http_dispatch(jsonb) from public, anon, authenticated;

create or replace function private.livekit_broadcast_disconnect_cron()
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  perform private.livekit_broadcast_disconnect_http_dispatch(
    jsonb_build_object('source', 'pg_cron')
  );
end;
$$;

revoke all on function private.livekit_broadcast_disconnect_cron() from public, anon, authenticated;

do $$
declare
  v_jobid bigint;
begin
  select jobid into v_jobid
  from cron.job
  where jobname = 'livekit-broadcast-disconnect-check';

  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
  end if;

  perform cron.schedule(
    'livekit-broadcast-disconnect-check',
    '* * * * *',
    $cron$select private.livekit_broadcast_disconnect_cron();$cron$
  );
end;
$$;
