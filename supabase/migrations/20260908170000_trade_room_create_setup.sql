-- Trade Room create/setup — category, tags, visibility, join policy, rules,
-- member permissions, join requests, atomic create RPC, and message guards.
--
-- Depends on: 20260908160000_official_trade_rooms_discovery.sql (room_kind, discovery_tags)

-- =============================================================================
-- 0. Prerequisites from official-rooms migration (idempotent if 160000 skipped)
-- =============================================================================

alter table public.rooms
  add column if not exists room_kind text not null default 'community';

alter table public.rooms
  add column if not exists discovery_tags text[] not null default '{}'::text[];

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'rooms_room_kind_check'
      and conrelid = 'public.rooms'::regclass
  ) then
    alter table public.rooms
      add constraint rooms_room_kind_check
      check (room_kind in ('community', 'official'));
  end if;
end $$;

-- =============================================================================
-- 1. Schema
-- =============================================================================

alter table public.rooms
  add column if not exists category text,
  add column if not exists join_policy text not null default 'open',
  add column if not exists rules text,
  add column if not exists members_can_message boolean not null default true,
  add column if not exists members_can_share_trades boolean not null default true,
  add column if not exists members_can_share_media boolean not null default true;

-- discovery_tags + is_private + room_kind already exist from prior migrations.

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

  if not exists (
    select 1 from pg_constraint
    where conname = 'rooms_category_check'
      and conrelid = 'public.rooms'::regclass
  ) then
    alter table public.rooms
      add constraint rooms_category_check
      check (
        category is null
        or category in (
          'futures', 'options', 'stocks', 'crypto', 'forex',
          'prop_firms', 'day_trading', 'swing_trading', 'general'
        )
      );
  end if;
end $$;

comment on column public.rooms.category is
  'Primary Trade Room category for discovery filters.';
comment on column public.rooms.join_policy is
  'open = anyone can join; approval = join requests required.';
comment on column public.rooms.rules is
  'Optional room guidelines shown to members.';
comment on column public.rooms.members_can_message is
  'When false, only the owner may post text messages (trade/media toggles apply separately).';
comment on column public.rooms.members_can_share_trades is
  'When false, non-owners cannot share trades in room messages.';
comment on column public.rooms.members_can_share_media is
  'When false, non-owners cannot share images/media in room messages.';

-- Preserve prior effective discovery behavior for legacy community rooms:
-- show_on_profile=false previously implied invite-link / hidden from discovery.
update public.rooms r
set is_private = true
where r.owner_user_id is not null
  and coalesce(r.room_kind, 'community') = 'community'
  and coalesce(r.show_on_profile, true) = false
  and coalesce(r.is_private, false) = false;

-- =============================================================================
-- 2. Join requests (approval policy)
-- =============================================================================

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

-- Block direct self-join when approval is required (owner row still inserted by create RPC).
drop policy if exists "room_members_insert_self" on public.room_members;
create policy "room_members_insert_self"
  on public.room_members
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and left_at is null
    and exists (
      select 1
      from public.rooms r
      where r.id = room_id
    )
    and not public.is_room_banned(room_id, auth.uid())
    and not exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and coalesce(p.is_banned, false)
    )
    and (
      public.is_room_owner(room_id, auth.uid())
      or exists (
        select 1
        from public.rooms r
        where r.id = room_id
          and coalesce(r.join_policy, 'open') = 'open'
      )
      or exists (
        select 1
        from public.room_join_requests jr
        where jr.room_id = room_id
          and jr.user_id = auth.uid()
          and jr.status = 'approved'
      )
    )
  );

-- =============================================================================
-- 3. Message permission guards (room-level + channel-level)
-- =============================================================================

create or replace function public.room_message_insert_allowed(
  p_room_id uuid,
  p_section_id uuid,
  p_user_id uuid,
  p_message_type text,
  p_trade_id uuid,
  p_image_url text,
  p_audio_url text
)
returns boolean
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_room record;
  v_type text := lower(trim(coalesce(p_message_type, 'text')));
begin
  if public.is_room_owner(p_room_id, p_user_id) then
    return true;
  end if;

  if exists (
    select 1 from public.admin_users au where au.user_id = p_user_id
  ) then
    return true;
  end if;

  select
    r.members_can_message,
    r.members_can_share_trades,
    r.members_can_share_media
  into v_room
  from public.rooms r
  where r.id = p_room_id;

  if not found then
    return false;
  end if;

  if p_section_id is not null then
    if exists (
      select 1
      from public.room_sections rs
      where rs.id = p_section_id
        and rs.room_id = p_room_id
        and coalesce(rs.allow_members_chat, true) = false
    ) then
      return false;
    end if;
  end if;

  if p_trade_id is not null or v_type = 'trade' then
    return coalesce(v_room.members_can_share_trades, true);
  end if;

  if coalesce(p_image_url, '') <> ''
     or coalesce(p_audio_url, '') <> ''
     or v_type in ('image', 'audio', 'voice')
  then
    return coalesce(v_room.members_can_share_media, true);
  end if;

  if v_type in ('post', 'reel', 'achievement', 'story') then
    return coalesce(v_room.members_can_share_media, true);
  end if;

  return coalesce(v_room.members_can_message, true);
end;
$$;

drop policy if exists "room_messages_insert_member" on public.room_messages;
create policy "room_messages_insert_member"
  on public.room_messages
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
    and public.room_message_insert_allowed(
      room_id,
      section_id,
      auth.uid(),
      type,
      trade_id,
      image_url,
      audio_url
    )
  );

-- =============================================================================
-- 4. Atomic create RPC
-- =============================================================================

create or replace function public.rpc_v1_create_trade_room(
  p_name text,
  p_description text default null,
  p_image_url text default null,
  p_show_on_profile boolean default true,
  p_is_private boolean default false,
  p_category text default null,
  p_discovery_tags text[] default '{}'::text[],
  p_join_policy text default 'open',
  p_rules text default null,
  p_members_can_message boolean default true,
  p_members_can_share_trades boolean default true,
  p_members_can_share_media boolean default true,
  p_channels jsonb default '[{"name":"general"}]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_username text;
  v_slug text;
  v_room public.rooms%rowtype;
  v_channel jsonb;
  v_channel_name text;
  v_position int := 0;
  v_seen_names text[] := '{}'::text[];
  v_tag_count int;
  v_join_policy text := lower(trim(coalesce(p_join_policy, 'open')));
  v_category text := nullif(lower(trim(coalesce(p_category, ''))), '');
  v_name text := trim(coalesce(p_name, ''));
  v_description text := nullif(trim(coalesce(p_description, '')), '');
  v_rules text := nullif(trim(coalesce(p_rules, '')), '');
  v_allow_chat boolean := coalesce(p_members_can_message, true);
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if v_name = '' then
    raise exception 'room_name_required' using errcode = '22023';
  end if;

  if char_length(v_name) > 100 then
    raise exception 'room_name_too_long' using errcode = '22023';
  end if;

  if v_description is not null and char_length(v_description) > 500 then
    raise exception 'room_description_too_long' using errcode = '22023';
  end if;

  if v_rules is not null and char_length(v_rules) > 2000 then
    raise exception 'room_rules_too_long' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.rooms r where r.owner_user_id = v_uid
  ) then
    raise exception 'owned_room_exists' using errcode = '23505';
  end if;

  if v_join_policy not in ('open', 'approval') then
    v_join_policy := 'open';
  end if;

  if v_category is not null and v_category not in (
    'futures', 'options', 'stocks', 'crypto', 'forex',
    'prop_firms', 'day_trading', 'swing_trading', 'general'
  ) then
    v_category := null;
  end if;

  v_tag_count := coalesce(array_length(p_discovery_tags, 1), 0);
  if v_tag_count > 5 then
    raise exception 'too_many_discovery_tags' using errcode = '22023';
  end if;

  if jsonb_typeof(p_channels) <> 'array' or jsonb_array_length(p_channels) < 1 then
    raise exception 'channels_required' using errcode = '22023';
  end if;

  if jsonb_array_length(p_channels) > 5 then
    raise exception 'too_many_channels' using errcode = '22023';
  end if;

  for v_channel in select * from jsonb_array_elements(p_channels)
  loop
    v_channel_name := trim(coalesce(v_channel->>'name', ''));
    if v_channel_name = '' then
      raise exception 'channel_name_required' using errcode = '22023';
    end if;
    if char_length(v_channel_name) > 64 then
      raise exception 'channel_name_too_long' using errcode = '22023';
    end if;
    if lower(v_channel_name) = any(v_seen_names) then
      raise exception 'duplicate_channel_name' using errcode = '22023';
    end if;
    v_seen_names := array_append(v_seen_names, lower(v_channel_name));
  end loop;

  select p.username into v_username
  from public.profiles p
  where p.id = v_uid;

  v_slug := coalesce(nullif(trim(v_username), ''), 'user')
    || '-' || (extract(epoch from clock_timestamp()) * 1000)::bigint::text;

  insert into public.rooms (
    name,
    description,
    owner_user_id,
    slug,
    image_url,
    show_on_profile,
    is_private,
    category,
    discovery_tags,
    join_policy,
    rules,
    members_can_message,
    members_can_share_trades,
    members_can_share_media,
    room_kind
  )
  values (
    v_name,
    coalesce(v_description, 'Personal Trade Room'),
    v_uid,
    v_slug,
    nullif(trim(coalesce(p_image_url, '')), ''),
    coalesce(p_show_on_profile, true),
    coalesce(p_is_private, false),
    v_category,
    coalesce(p_discovery_tags, '{}'::text[]),
    v_join_policy,
    v_rules,
    coalesce(p_members_can_message, true),
    coalesce(p_members_can_share_trades, true),
    coalesce(p_members_can_share_media, true),
    'community'
  )
  returning * into v_room;

  v_position := 0;
  for v_channel in select * from jsonb_array_elements(p_channels)
  loop
    v_position := v_position + 1;
    v_channel_name := trim(v_channel->>'name');
    insert into public.room_sections (room_id, name, position, allow_members_chat)
    values (v_room.id, v_channel_name, v_position, v_allow_chat);
  end loop;

  insert into public.room_members (room_id, user_id, notification_enabled)
  values (v_room.id, v_uid, true);

  perform public.ensure_room_member_tags_defaults(v_room.id);

  return jsonb_build_object(
    'id', v_room.id,
    'name', v_room.name,
    'description', v_room.description,
    'slug', v_room.slug,
    'image_url', v_room.image_url,
    'owner_user_id', v_room.owner_user_id,
    'show_on_profile', coalesce(v_room.show_on_profile, true),
    'is_private', coalesce(v_room.is_private, false),
    'category', v_room.category,
    'discovery_tags', coalesce(to_jsonb(v_room.discovery_tags), '[]'::jsonb),
    'join_policy', v_room.join_policy,
    'rules', v_room.rules,
    'members_can_message', coalesce(v_room.members_can_message, true),
    'members_can_share_trades', coalesce(v_room.members_can_share_trades, true),
    'members_can_share_media', coalesce(v_room.members_can_share_media, true),
    'room_kind', coalesce(v_room.room_kind, 'community'),
    'member_count', 1
  );
end;
$$;

comment on function public.rpc_v1_create_trade_room is
  'Atomic community Trade Room creation — room, channels, owner membership, default member tags.';

revoke all on function public.rpc_v1_create_trade_room from public;
grant execute on function public.rpc_v1_create_trade_room to authenticated;

-- Request to join (approval policy rooms).
create or replace function public.rpc_v1_request_trade_room_join(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_request public.room_join_requests%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
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
    where room_id = p_room_id and user_id = v_uid;
  end if;

  return jsonb_build_object(
    'id', v_request.id,
    'room_id', v_request.room_id,
    'user_id', v_request.user_id,
    'status', v_request.status
  );
end;
$$;

grant execute on function public.rpc_v1_request_trade_room_join(uuid) to authenticated;
