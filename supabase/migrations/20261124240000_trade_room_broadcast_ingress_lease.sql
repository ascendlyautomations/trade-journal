-- Cross-instance OBS ingress creation lease (prevents duplicate LiveKit Ingress per session).

alter table public.room_live_broadcasts
  add column if not exists ingress_creation_lease_token uuid,
  add column if not exists ingress_creation_lease_at timestamptz;

comment on column public.room_live_broadcasts.ingress_creation_lease_token is
  'Ephemeral lease while POST /obs/credentials creates LiveKit Ingress; cleared on attach or release.';
comment on column public.room_live_broadcasts.ingress_creation_lease_at is
  'Lease start time; stale leases can be reclaimed after TTL.';

create or replace function public.trade_room_broadcast_claim_ingress_lease(
  p_session_id uuid,
  p_room_id uuid,
  p_broadcaster_id uuid,
  p_ttl_seconds int default 180
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.room_live_broadcasts%rowtype;
  v_token uuid := gen_random_uuid();
  v_cutoff timestamptz := now() - make_interval(secs => greatest(p_ttl_seconds, 30));
begin
  select *
  into v_row
  from public.room_live_broadcasts
  where id = p_session_id
    and room_id = p_room_id
    and ended_at is null
  for update;

  if not found then
    return 'NOT_FOUND';
  end if;

  if v_row.broadcaster_user_id <> p_broadcaster_id then
    return 'FORBIDDEN';
  end if;

  if coalesce(trim(v_row.livekit_ingress_id), '') <> '' then
    return 'ALREADY_ATTACHED';
  end if;

  if v_row.ingress_creation_lease_token is not null
     and v_row.ingress_creation_lease_at is not null
     and v_row.ingress_creation_lease_at > v_cutoff then
    return 'IN_PROGRESS:' || v_row.ingress_creation_lease_token::text;
  end if;

  update public.room_live_broadcasts
  set
    ingress_creation_lease_token = v_token,
    ingress_creation_lease_at = now(),
    ingress_status_snapshot = coalesce(ingress_status_snapshot, 'CREATING')
  where id = p_session_id
    and room_id = p_room_id
    and ended_at is null;

  return 'CLAIMED:' || v_token::text;
end;
$$;

create or replace function public.trade_room_broadcast_release_ingress_lease(
  p_session_id uuid,
  p_room_id uuid,
  p_broadcaster_id uuid,
  p_lease_token uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.room_live_broadcasts
  set
    ingress_creation_lease_token = null,
    ingress_creation_lease_at = null,
    ingress_status_snapshot = case
      when coalesce(trim(livekit_ingress_id), '') = '' then null
      else ingress_status_snapshot
    end
  where id = p_session_id
    and room_id = p_room_id
    and broadcaster_user_id = p_broadcaster_id
    and ended_at is null
    and (
      p_lease_token is null
      or ingress_creation_lease_token = p_lease_token
    );

  return found;
end;
$$;

create or replace function public.trade_room_broadcast_commit_ingress(
  p_session_id uuid,
  p_room_id uuid,
  p_broadcaster_id uuid,
  p_lease_token uuid,
  p_ingress_id text,
  p_primary_identity text,
  p_status_label text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.room_live_broadcasts
  set
    broadcast_source = 'obs',
    primary_media_publisher_identity = nullif(trim(p_primary_identity), ''),
    livekit_ingress_id = nullif(trim(p_ingress_id), ''),
    ingress_status_snapshot = nullif(trim(p_status_label), ''),
    ingress_creation_lease_token = null,
    ingress_creation_lease_at = null,
    last_livekit_signal_at = now()
  where id = p_session_id
    and room_id = p_room_id
    and broadcaster_user_id = p_broadcaster_id
    and ended_at is null
    and coalesce(trim(livekit_ingress_id), '') = ''
    and (
      ingress_creation_lease_token = p_lease_token
      or (p_lease_token is null and ingress_creation_lease_token is null)
    );

  return found;
end;
$$;

comment on function public.trade_room_broadcast_claim_ingress_lease(uuid, uuid, uuid, int) is
  'Returns CLAIMED:<token>, IN_PROGRESS:<token>, ALREADY_ATTACHED, NOT_FOUND, or FORBIDDEN.';