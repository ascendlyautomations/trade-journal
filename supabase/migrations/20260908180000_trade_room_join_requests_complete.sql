-- Trade Room join requests — discovery viewer state, owner approve/decline RPCs,
-- and hardened request submission.
--
-- Depends on: 20260908170000_trade_room_create_setup.sql (room_join_requests, join_policy)
-- Safe to rerun: section 0 is idempotent when 170000 already applied.

-- =============================================================================
-- 0. Prerequisites (idempotent — ensures table/columns exist before RPC compile)
-- =============================================================================

alter table public.rooms
  add column if not exists room_kind text not null default 'community';

alter table public.rooms
  add column if not exists discovery_tags text[] not null default '{}'::text[];

alter table public.rooms
  add column if not exists join_policy text not null default 'open';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'rooms_join_policy_check'
      and conrelid = 'public.rooms'::regclass
  ) then
    alter table public.rooms
      add constraint rooms_join_policy_check
      check (join_policy in ('open', 'approval'));
  end if;
end $$;

create table if not exists public.room_join_requests (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default timezone('utc', now()),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id) on delete set null,
  unique (room_id, user_id)
);

create index if not exists room_join_requests_room_status_idx
  on public.room_join_requests (room_id, status);

alter table public.room_join_requests enable row level security;

drop policy if exists "room_join_requests_select_participant" on public.room_join_requests;
create policy "room_join_requests_select_participant"
  on public.room_join_requests
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or public.is_room_owner(room_id, auth.uid())
  );

drop policy if exists "room_join_requests_insert_self" on public.room_join_requests;
create policy "room_join_requests_insert_self"
  on public.room_join_requests
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and status = 'pending'
    and exists (
      select 1
      from public.rooms r
      where r.id = room_id
        and r.join_policy = 'approval'
        and coalesce(r.is_private, false) = false
    )
    and not public.is_room_banned(room_id, auth.uid())
    and not public.is_active_room_member(room_id, auth.uid())
  );

drop policy if exists "room_join_requests_update_owner" on public.room_join_requests;
create policy "room_join_requests_update_owner"
  on public.room_join_requests
  for update
  to authenticated
  using (public.is_room_owner(room_id, auth.uid()))
  with check (public.is_room_owner(room_id, auth.uid()));

-- =============================================================================
-- 1. Harden request RPC (ban/private/member guards)
-- =============================================================================

create or replace function public.rpc_v1_request_trade_room_join(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_room record;
  v_request public.room_join_requests%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_room_id is null then
    raise exception 'room_id_required' using errcode = '22023';
  end if;

  select
    r.id,
    r.join_policy,
    coalesce(r.is_private, false) as is_private,
    r.owner_user_id
  into v_room
  from public.rooms r
  where r.id = p_room_id;

  if not found then
    raise exception 'room_not_found' using errcode = 'P0002';
  end if;

  if v_room.is_private then
    raise exception 'room_not_requestable' using errcode = '42501';
  end if;

  if coalesce(v_room.join_policy, 'open') <> 'approval' then
    raise exception 'room_open_join' using errcode = '22023';
  end if;

  if public.is_room_banned(p_room_id, v_uid) then
    raise exception 'room_banned' using errcode = '42501';
  end if;

  if public.is_active_room_member(p_room_id, v_uid) then
    raise exception 'already_member' using errcode = '23505';
  end if;

  if exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and coalesce(p.is_banned, false)
  ) then
    raise exception 'platform_banned' using errcode = '42501';
  end if;

  insert into public.room_join_requests (room_id, user_id, status)
  values (p_room_id, v_uid, 'pending')
  on conflict (room_id, user_id) do update
    set status = 'pending',
        resolved_at = null,
        resolved_by = null
  where public.room_join_requests.status <> 'pending'
  returning * into v_request;

  if v_request.id is null then
    select * into v_request
    from public.room_join_requests
    where room_id = p_room_id
      and user_id = v_uid;
  end if;

  return jsonb_build_object(
    'id', v_request.id,
    'room_id', v_request.room_id,
    'user_id', v_request.user_id,
    'status', v_request.status,
    'created_at', v_request.created_at
  );
end;
$$;

grant execute on function public.rpc_v1_request_trade_room_join(uuid) to authenticated;

-- =============================================================================
-- 2. Owner list + resolve RPCs
-- =============================================================================

create or replace function public.rpc_v1_list_trade_room_join_requests(
  p_room_id uuid,
  p_status text default 'pending'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_status text := lower(trim(coalesce(p_status, 'pending')));
  v_requests jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not public.is_room_owner(p_room_id, v_uid) then
    raise exception 'room_owner_required' using errcode = '42501';
  end if;

  if v_status not in ('pending', 'approved', 'rejected', 'all') then
    v_status := 'pending';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', jr.id,
        'room_id', jr.room_id,
        'user_id', jr.user_id,
        'status', jr.status,
        'created_at', jr.created_at,
        'resolved_at', jr.resolved_at,
        'profile', jsonb_build_object(
          'id', p.id,
          'username', p.username,
          'name', p.name,
          'avatar_url', p.avatar_url
        )
      )
      order by jr.created_at asc
    ),
    '[]'::jsonb
  )
  into v_requests
  from public.room_join_requests jr
  inner join public.profiles p on p.id = jr.user_id
  where jr.room_id = p_room_id
    and (
      v_status = 'all'
      or jr.status = v_status
    );

  return jsonb_build_object(
    'room_id', p_room_id,
    'pending_count', (
      select count(*)::int
      from public.room_join_requests jr2
      where jr2.room_id = p_room_id
        and jr2.status = 'pending'
    ),
    'requests', v_requests
  );
end;
$$;

grant execute on function public.rpc_v1_list_trade_room_join_requests(uuid, text) to authenticated;

create or replace function public.rpc_v1_resolve_trade_room_join_request(
  p_request_id uuid,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_action text := lower(trim(coalesce(p_action, '')));
  v_request public.room_join_requests%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if v_action not in ('approve', 'decline') then
    raise exception 'invalid_action' using errcode = '22023';
  end if;

  select * into v_request
  from public.room_join_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'request_not_found' using errcode = 'P0002';
  end if;

  if not public.is_room_owner(v_request.room_id, v_uid) then
    raise exception 'room_owner_required' using errcode = '42501';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'request_not_pending' using errcode = '22023';
  end if;

  if public.is_room_banned(v_request.room_id, v_request.user_id) then
    update public.room_join_requests
    set status = 'rejected',
        resolved_at = timezone('utc', now()),
        resolved_by = v_uid
    where id = v_request.id;
    raise exception 'user_banned' using errcode = '42501';
  end if;

  if v_action = 'decline' then
    update public.room_join_requests
    set status = 'rejected',
        resolved_at = timezone('utc', now()),
        resolved_by = v_uid
    where id = v_request.id
    returning * into v_request;

    return jsonb_build_object(
      'id', v_request.id,
      'room_id', v_request.room_id,
      'user_id', v_request.user_id,
      'status', v_request.status
    );
  end if;

  -- approve
  update public.room_join_requests
  set status = 'approved',
      resolved_at = timezone('utc', now()),
      resolved_by = v_uid
  where id = v_request.id
  returning * into v_request;

  insert into public.room_members (room_id, user_id, notification_enabled, left_at)
  values (v_request.room_id, v_request.user_id, true, null)
  on conflict do nothing;

  -- Soft-leave rejoin path
  update public.room_members
  set left_at = null,
      notification_enabled = true
  where room_id = v_request.room_id
    and user_id = v_request.user_id
    and left_at is not null;

  if not exists (
    select 1
    from public.room_members rm
    where rm.room_id = v_request.room_id
      and rm.user_id = v_request.user_id
      and rm.left_at is null
  ) then
    insert into public.room_members (room_id, user_id, notification_enabled)
    values (v_request.room_id, v_request.user_id, true);
  end if;

  return jsonb_build_object(
    'id', v_request.id,
    'room_id', v_request.room_id,
    'user_id', v_request.user_id,
    'status', v_request.status
  );
end;
$$;

grant execute on function public.rpc_v1_resolve_trade_room_join_request(uuid, text) to authenticated;

-- Viewer join-request lookup for room preview / conversation bootstrap.
create or replace function public.rpc_v1_viewer_trade_room_join_request(p_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_request public.room_join_requests%rowtype;
begin
  if v_uid is null then
    return jsonb_build_object('status', null);
  end if;

  select * into v_request
  from public.room_join_requests
  where room_id = p_room_id
    and user_id = v_uid;

  if not found then
    return jsonb_build_object('status', null);
  end if;

  return jsonb_build_object(
    'id', v_request.id,
    'room_id', v_request.room_id,
    'user_id', v_request.user_id,
    'status', v_request.status,
    'created_at', v_request.created_at
  );
end;
$$;

grant execute on function public.rpc_v1_viewer_trade_room_join_request(uuid) to authenticated;

-- =============================================================================
-- 3. Discovery RPC — join_policy + viewer request status
-- =============================================================================

drop function if exists public.rpc_v1_trade_room_discovery(text, int, text);

create or replace function public.rpc_v1_trade_room_discovery(
  p_mode text default 'popular',
  p_limit int default 20,
  p_scope text default 'all'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_mode text := lower(trim(coalesce(p_mode, 'popular')));
  v_scope text := lower(trim(coalesce(p_scope, 'all')));
  v_limit int := greatest(1, least(coalesce(p_limit, 20), 50));
  v_match_slug text := public.trade_room_suggested_official_slug(v_uid);
  v_rooms jsonb := '[]'::jsonb;
begin
  if v_mode not in ('popular', 'suggested') then
    v_mode := 'popular';
  end if;
  if v_scope not in ('all', 'official', 'community') then
    v_scope := 'all';
  end if;

  with followed_counts as (
    select
      rm.room_id,
      count(distinct rm.user_id)::int as followed_member_count
    from public.room_members rm
    inner join public.followers f
      on f.following_id = rm.user_id
      and f.follower_id = v_uid
    where rm.left_at is null
      and v_uid is not null
    group by rm.room_id
  ),
  recent_activity as (
    select
      rm.room_id,
      count(*)::int as recent_message_count
    from public.room_messages rm
    where rm.created_at > (timezone('utc', now()) - interval '7 days')
    group by rm.room_id
  ),
  eligible as (
    select
      r.id,
      r.name,
      r.description,
      r.slug,
      r.image_url,
      r.room_kind,
      r.discovery_tags,
      r.join_policy,
      r.owner_user_id,
      p.username as owner_username,
      p.name as owner_name,
      p.avatar_url as owner_avatar_url,
      vjr.status as viewer_join_request_status,
      count(m.user_id) filter (where m.left_at is null) as member_count,
      coalesce(fc.followed_member_count, 0) as followed_member_count,
      coalesce(ra.recent_message_count, 0) as recent_message_count,
      case
        when v_mode = 'suggested'
          and r.room_kind = 'official'
          and lower(trim(coalesce(r.slug, ''))) = coalesce(v_match_slug, '')
        then 1000
        else 0
      end as suggested_boost
    from public.rooms r
    left join public.profiles p
      on p.id = r.owner_user_id
      and coalesce(p.is_private, false) = false
    left join public.room_members m
      on m.room_id = r.id
    left join followed_counts fc
      on fc.room_id = r.id
    left join recent_activity ra
      on ra.room_id = r.id
    left join public.room_join_requests vjr
      on vjr.room_id = r.id
      and vjr.user_id = v_uid
    where lower(trim(coalesce(r.slug, ''))) <> 'tradetraxs-beta'
      and coalesce(r.show_on_profile, true) = true
      and coalesce(r.is_private, false) = false
      and (
        v_scope = 'all'
        or (v_scope = 'official' and r.room_kind = 'official')
        or (v_scope = 'community' and r.room_kind = 'community')
      )
      and (
        r.room_kind = 'official'
        or (
          r.room_kind = 'community'
          and r.owner_user_id is not null
          and p.id is not null
        )
      )
      and (
        v_uid is null
        or not exists (
          select 1
          from public.room_members vm
          where vm.room_id = r.id
            and vm.user_id = v_uid
            and vm.left_at is null
        )
      )
      and (
        v_uid is null
        or not public.is_room_banned(r.id, v_uid)
      )
    group by
      r.id,
      r.name,
      r.description,
      r.slug,
      r.image_url,
      r.room_kind,
      r.discovery_tags,
      r.join_policy,
      r.owner_user_id,
      p.username,
      p.name,
      p.avatar_url,
      vjr.status,
      fc.followed_member_count,
      ra.recent_message_count
  ),
  ranked as (
    select *
    from eligible
    order by
      case when v_mode = 'suggested' then suggested_boost else 0 end desc,
      case when v_mode = 'suggested' then followed_member_count else 0 end desc,
      member_count desc,
      recent_message_count desc,
      name asc
    limit v_limit
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'name', name,
        'description', description,
        'slug', slug,
        'member_count', member_count,
        'image_url', image_url,
        'room_kind', room_kind,
        'discovery_tags', coalesce(to_jsonb(discovery_tags), '[]'::jsonb),
        'join_policy', coalesce(join_policy, 'open'),
        'viewer_join_request_status', viewer_join_request_status,
        'followed_member_count', followed_member_count,
        'recent_message_count', recent_message_count,
        'owner', case
          when owner_user_id is null then null
          else jsonb_build_object(
            'id', owner_user_id,
            'username', owner_username,
            'name', owner_name,
            'avatar_url', owner_avatar_url
          )
        end
      )
      order by
        case when v_mode = 'suggested' then suggested_boost else 0 end desc,
        case when v_mode = 'suggested' then followed_member_count else 0 end desc,
        member_count desc,
        recent_message_count desc,
        name asc
    ),
    '[]'::jsonb
  )
  into v_rooms
  from ranked;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_jsonb(timezone('utc', now())),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object(
      'mode', v_mode,
      'scope', v_scope,
      'rooms', v_rooms
    )
  );
end;
$$;

grant execute on function public.rpc_v1_trade_room_discovery(text, int, text) to authenticated, anon;

-- =============================================================================
-- 4. Native/shared rich search RPC (web keeps legacy search_public_trade_rooms)
-- =============================================================================

create or replace function public.rpc_v1_search_trade_rooms(
  p_query text,
  p_limit int default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_limit int := greatest(1, least(coalesce(p_limit, 20), 50));
  v_term text := trim(coalesce(p_query, ''));
  v_rooms jsonb := '[]'::jsonb;
begin
  if v_term = '' then
    return jsonb_build_object(
      'meta', jsonb_build_object('contract_version', 'v1'),
      'data', jsonb_build_object('rooms', '[]'::jsonb)
    );
  end if;

  with eligible as (
    select
      r.id,
      r.name,
      r.description,
      r.slug,
      r.image_url,
      r.room_kind,
      r.discovery_tags,
      coalesce(r.join_policy, 'open') as join_policy,
      vjr.status as viewer_join_request_status,
      count(m.user_id) filter (where m.left_at is null) as member_count,
      (
        v_uid is not null
        and exists (
          select 1
          from public.room_members vm
          where vm.room_id = r.id
            and vm.user_id = v_uid
            and vm.left_at is null
        )
      ) as is_member
    from public.rooms r
    left join public.profiles p
      on p.id = r.owner_user_id
      and coalesce(p.is_private, false) = false
    left join public.room_members m
      on m.room_id = r.id
    left join public.room_join_requests vjr
      on vjr.room_id = r.id
      and vjr.user_id = v_uid
    where lower(trim(coalesce(r.slug, ''))) <> 'tradetraxs-beta'
      and coalesce(r.show_on_profile, true) = true
      and coalesce(r.is_private, false) = false
      and (
        coalesce(r.room_kind, 'community') = 'official'
        or (
          coalesce(r.room_kind, 'community') = 'community'
          and r.owner_user_id is not null
          and p.id is not null
        )
      )
      and (
        r.name ilike '%' || v_term || '%'
        or r.slug ilike '%' || v_term || '%'
        or coalesce(r.description, '') ilike '%' || v_term || '%'
        or exists (
          select 1
          from unnest(coalesce(r.discovery_tags, '{}'::text[])) tag
          where tag ilike '%' || v_term || '%'
        )
      )
    group by
      r.id, r.name, r.description, r.slug, r.image_url, r.room_kind,
      r.discovery_tags, r.join_policy, vjr.status
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'name', name,
        'description', description,
        'slug', slug,
        'member_count', member_count,
        'image_url', image_url,
        'room_kind', room_kind,
        'discovery_tags', coalesce(to_jsonb(discovery_tags), '[]'::jsonb),
        'join_policy', join_policy,
        'viewer_join_request_status', viewer_join_request_status,
        'is_member', is_member
      )
      order by
        case when coalesce(room_kind, 'community') = 'official' then 0 else 1 end,
        member_count desc,
        name asc
    ),
    '[]'::jsonb
  )
  into v_rooms
  from (
    select * from eligible
    order by
      case when coalesce(room_kind, 'community') = 'official' then 0 else 1 end,
      member_count desc,
      name asc
    limit v_limit
  ) ranked;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_jsonb(timezone('utc', now())),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object('rooms', v_rooms)
  );
end;
$$;

comment on function public.rpc_v1_search_trade_rooms(text, int) is
  'Rich Trade Room search for native/shared clients. Web continues using search_public_trade_rooms.';

grant execute on function public.rpc_v1_search_trade_rooms(text, int) to authenticated, anon;
