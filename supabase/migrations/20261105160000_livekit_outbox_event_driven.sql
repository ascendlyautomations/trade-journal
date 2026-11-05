-- LiveKit disconnect outbox: event-driven dispatch (pg_net) + pg_cron retries (no Vercel cron).

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema extensions;

alter table public.room_livekit_disconnect_outbox
  add column if not exists attempt_count integer not null default 0;

alter table public.room_livekit_disconnect_outbox
  add column if not exists processing_claimed_at timestamptz;

comment on column public.room_livekit_disconnect_outbox.processing_claimed_at is
  'Claim lease for concurrent BFF workers; stale after 5 minutes.';

-- Processing-time guard: skip stale rows when the user was reinstated.
create or replace function public.room_livekit_should_disconnect(
  p_room_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_room_banned(p_room_id, p_user_id)
    or not public.is_active_room_member(p_room_id, p_user_id);
$$;

comment on function public.room_livekit_should_disconnect(uuid, uuid) is
  'True when LiveKit participant should be removed (banned or not an active member).';

revoke all on function public.room_livekit_should_disconnect(uuid, uuid) from public;
grant execute on function public.room_livekit_should_disconnect(uuid, uuid) to service_role;

create or replace function public.room_livekit_claim_outbox(
  p_limit integer default 20,
  p_outbox_id uuid default null
)
returns setof public.room_livekit_disconnect_outbox
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with candidates as (
    select o.id
    from public.room_livekit_disconnect_outbox o
    where o.processed_at is null
      and (p_outbox_id is null or o.id = p_outbox_id)
      and (
        o.processing_claimed_at is null
        or o.processing_claimed_at < timezone('utc', now()) - interval '5 minutes'
      )
    order by o.created_at asc
    limit greatest(1, least(coalesce(p_limit, 20), 100))
    for update skip locked
  )
  update public.room_livekit_disconnect_outbox o
  set
    processing_claimed_at = timezone('utc', now()),
    attempt_count = o.attempt_count + 1
  from candidates c
  where o.id = c.id
  returning o.*;
end;
$$;

comment on function public.room_livekit_claim_outbox(integer, uuid) is
  'Atomically claims pending outbox rows for BFF LiveKit disconnect processing.';

revoke all on function public.room_livekit_claim_outbox(integer, uuid) from public;
grant execute on function public.room_livekit_claim_outbox(integer, uuid) to service_role;

-- BFF URL + bearer secret for pg_net / pg_cron (configure per environment after deploy).
create schema if not exists private;

create table if not exists private.livekit_outbox_processor_config (
  id smallint primary key check (id = 1),
  bff_process_url text not null,
  bearer_secret text not null,
  updated_at timestamptz not null default timezone('utc', now())
);

comment on table private.livekit_outbox_processor_config is
  'Single-row config: POST URL (e.g. https://www.tradetraxs.com/api/internal/livekit/process-outbox) and Bearer secret matching LIVEKIT_OUTBOX_WEBHOOK_SECRET on Vercel.';

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to postgres, service_role;
revoke all on table private.livekit_outbox_processor_config from public, anon, authenticated;
grant select on table private.livekit_outbox_processor_config to postgres, service_role;

create or replace function private.livekit_outbox_http_dispatch(p_body jsonb)
returns bigint
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_url text;
  v_secret text;
  v_request_id bigint;
begin
  select c.bff_process_url, c.bearer_secret
  into v_url, v_secret
  from private.livekit_outbox_processor_config c
  where c.id = 1;

  if v_url is null or v_secret is null or length(trim(v_url)) = 0 then
    return null;
  end if;

  select net.http_post(
    url := trim(v_url),
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

revoke all on function private.livekit_outbox_http_dispatch(jsonb) from public, anon, authenticated;

create or replace function private.trg_room_livekit_outbox_after_insert_dispatch()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  perform private.livekit_outbox_http_dispatch(
    jsonb_build_object(
      'outboxId', new.id::text,
      'source', 'pg_trigger'
    )
  );
  return new;
end;
$$;

drop trigger if exists room_livekit_outbox_dispatch on public.room_livekit_disconnect_outbox;
create trigger room_livekit_outbox_dispatch
  after insert on public.room_livekit_disconnect_outbox
  for each row
  execute function private.trg_room_livekit_outbox_after_insert_dispatch();

create or replace function private.livekit_outbox_cron_retry()
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  perform private.livekit_outbox_http_dispatch(
    jsonb_build_object('source', 'pg_cron')
  );
end;
$$;

revoke all on function private.livekit_outbox_cron_retry() from public, anon, authenticated;

do $$
declare
  v_jobid bigint;
begin
  select jobid into v_jobid
  from cron.job
  where jobname = 'livekit-outbox-retry';

  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
  end if;

  perform cron.schedule(
    'livekit-outbox-retry',
    '*/5 * * * *',
    $cron$select private.livekit_outbox_cron_retry();$cron$
  );
end;
$$;

comment on table public.room_livekit_disconnect_outbox is
  'Server-only queue: ban/kick/leave → LiveKit RemoveParticipant via BFF (pg_net on insert + pg_cron retry).';
