-- Phase 1: Security & privacy — trading accounts RLS, private room authorization,
-- join/rejoin guards, invite lookup RPC, moderator ban-delete scope.

-- =============================================================================
-- 1. public.accounts — owner-only RLS (additive; service role unchanged)
-- =============================================================================

alter table public.accounts enable row level security;

drop policy if exists "accounts_select_own" on public.accounts;
create policy "accounts_select_own"
  on public.accounts
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "accounts_insert_own" on public.accounts;
create policy "accounts_insert_own"
  on public.accounts
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "accounts_update_own" on public.accounts;
create policy "accounts_update_own"
  on public.accounts
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "accounts_delete_own" on public.accounts;
create policy "accounts_delete_own"
  on public.accounts
  for delete
  to authenticated
  using (user_id = auth.uid());

-- Legacy permissive names (safe if absent)
drop policy if exists "Allow read accounts" on public.accounts;
drop policy if exists "Users can view own accounts" on public.accounts;
drop policy if exists "Users can insert own accounts" on public.accounts;
drop policy if exists "Users can update own accounts" on public.accounts;
drop policy if exists "Users can delete own accounts" on public.accounts;
drop policy if exists "TEMP allow all accounts" on public.accounts;

grant select, insert, update, delete on table public.accounts to authenticated;

comment on table public.accounts is
  'Trading accounts journal metadata. RLS restricts authenticated access to user_id = auth.uid(); integrations use service role or security definer RPCs.';

-- =============================================================================
-- 2. public.rooms — tighten SELECT; stop listing private rooms by owner/slug
-- =============================================================================

drop policy if exists "rooms_select_profile_public" on public.rooms;
create policy "rooms_select_profile_public"
  on public.rooms
  for select
  to anon, authenticated
  using (
    owner_user_id is not null
    and coalesce(is_private, false) = false
    and coalesce(show_on_profile, true) = true
  );

drop policy if exists "rooms_select_invite" on public.rooms;
create policy "rooms_select_invite"
  on public.rooms
  for select
  to authenticated
  using (
    owner_user_id is null
  );

-- Private rooms stored with open join_policy bypassed discovery; normalize to approval.
update public.rooms
set join_policy = 'approval'
where coalesce(is_private, false) = true
  and coalesce(join_policy, 'open') = 'open';

-- =============================================================================
-- 3. Invite / deep-link lookup (capability URL — not enumerable private listing)
-- =============================================================================

create or replace function public.rpc_v1_trade_room_invite_lookup(p_ref text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_ref text := trim(coalesce(p_ref, ''));
  v_room public.rooms%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if v_ref = '' then
    return null;
  end if;

  if v_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into v_room from public.rooms where id = v_ref::uuid;
  else
    select * into v_room
    from public.rooms
    where lower(trim(coalesce(slug, ''))) = lower(v_ref)
    limit 1;
  end if;

  if not found then
    return null;
  end if;

  if public.is_room_banned(v_room.id, v_uid) then
    raise exception 'room_banned' using errcode = '42501';
  end if;

  if coalesce(v_room.is_private, false)
     and v_room.owner_user_id is distinct from v_uid
     and not public.is_active_room_member(v_room.id, v_uid)
  then
    return jsonb_build_object(
      'id', v_room.id,
      'name', v_room.name,
      'description', v_room.description,
      'slug', v_room.slug,
      'image_url', v_room.image_url,
      'owner_user_id', v_room.owner_user_id,
      'show_on_profile', coalesce(v_room.show_on_profile, true),
      'is_private', true,
      'category', v_room.category,
      'discovery_tags', coalesce(to_jsonb(v_room.discovery_tags), '[]'::jsonb),
      'join_policy', 'approval',
      'rules', v_room.rules,
      'members_can_message', coalesce(v_room.members_can_message, true),
      'members_can_share_trades', coalesce(v_room.members_can_share_trades, true),
      'members_can_share_media', coalesce(v_room.members_can_share_media, true),
      'room_kind', coalesce(v_room.room_kind, 'community'),
      'created_at', v_room.created_at
    );
  end if;

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
    'created_at', v_room.created_at
  );
end;
$$;

comment on function public.rpc_v1_trade_room_invite_lookup(text) is
  'Resolve Trade Room by slug or UUID for invite/deep links. Does not expose private rooms except invite preview fields.';

revoke all on function public.rpc_v1_trade_room_invite_lookup(text) from public;
grant execute on function public.rpc_v1_trade_room_invite_lookup(text) to authenticated;

-- =============================================================================
-- 4. room_members — block open join / rejoin on private rooms
-- =============================================================================

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
      where r.id = room_members.room_id
    )
    and not public.is_room_banned(room_members.room_id, auth.uid())
    and not exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and coalesce(p.is_banned, false)
    )
    and (
      public.is_room_owner(room_members.room_id, auth.uid())
      or (
        exists (
          select 1
          from public.rooms r
          where r.id = room_members.room_id
            and coalesce(r.is_private, false) = false
            and coalesce(r.join_policy, 'open') = 'open'
        )
      )
      or exists (
        select 1
        from public.room_join_requests jr
        where jr.room_id = room_members.room_id
          and jr.user_id = auth.uid()
          and jr.status = 'approved'
      )
    )
  );

create or replace function public.room_members_before_update_guard()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.room_id is distinct from new.room_id
     or old.user_id is distinct from new.user_id
  then
    raise exception 'room_id and user_id are immutable on room_members';
  end if;

  if old.left_at is not null and new.left_at is null then
    if public.is_room_banned(new.room_id, new.user_id) then
      raise exception 'banned from this room';
    end if;

    if not (
      public.is_room_owner(new.room_id, new.user_id)
      or exists (
        select 1
        from public.rooms r
        where r.id = new.room_id
          and coalesce(r.is_private, false) = false
          and coalesce(r.join_policy, 'open') = 'open'
      )
      or exists (
        select 1
        from public.room_join_requests jr
        where jr.room_id = new.room_id
          and jr.user_id = new.user_id
          and jr.status = 'approved'
      )
    ) then
      raise exception 'room_join_not_allowed' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

-- =============================================================================
-- 5. room_join_requests — allow private rooms (approval-only)
-- =============================================================================

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
        and (
          coalesce(r.is_private, false) = true
          or coalesce(r.join_policy, 'open') = 'approval'
        )
    )
    and not public.is_room_banned(room_id, auth.uid())
    and not public.is_active_room_member(room_id, auth.uid())
  );

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

  if not v_room.is_private
     and coalesce(v_room.join_policy, 'open') <> 'approval'
  then
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
-- 6. Create room — private rooms always approval join
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
  v_room_allow_chat boolean := coalesce(p_members_can_message, true);
  v_channel_allow_chat boolean;
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

  if coalesce(p_is_private, false) then
    v_join_policy := 'approval';
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
    if v_channel ? 'allow_members_chat' then
      v_channel_allow_chat := coalesce((v_channel->>'allow_members_chat')::boolean, v_room_allow_chat);
    else
      v_channel_allow_chat := v_room_allow_chat;
    end if;
    insert into public.room_sections (room_id, name, position, allow_members_chat)
    values (v_room.id, v_channel_name, v_position, v_channel_allow_chat);
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

revoke all on function public.rpc_v1_create_trade_room(
  text, text, text, boolean, boolean, text, text[], text, text, boolean, boolean, boolean, jsonb
) from public;
grant execute on function public.rpc_v1_create_trade_room(
  text, text, text, boolean, boolean, text, text[], text, text, boolean, boolean, boolean, jsonb
) to authenticated;

-- =============================================================================
-- 7. room_bans — moderators may only lift bans they issued; owners any ban
-- =============================================================================

drop policy if exists "room_bans_delete_moderator" on public.room_bans;
create policy "room_bans_delete_moderator"
  on public.room_bans
  for delete
  to authenticated
  using (
    public.can_manage_trade_room(room_id, auth.uid())
    or (
      public.can_moderate_trade_room(room_id, auth.uid())
      and not public.can_manage_trade_room(room_id, auth.uid())
      and banned_by = auth.uid()
    )
  );
