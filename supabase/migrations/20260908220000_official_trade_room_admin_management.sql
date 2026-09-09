-- Official Trade Room admin management: platform admins (admin_users) may manage
-- official rooms using the same RLS/RPC paths as community room owners.

-- =============================================================================
-- 1. Authoritative management gate
-- =============================================================================

create or replace function public.can_manage_trade_room(
  p_room_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select
    public.is_room_owner(p_room_id, p_user_id)
    or (
      exists (
        select 1
        from public.admin_users au
        where au.user_id = p_user_id
      )
      and exists (
        select 1
        from public.rooms r
        where r.id = p_room_id
          and r.room_kind = 'official'
      )
    );
$$;

comment on function public.can_manage_trade_room(uuid, uuid) is
  'True when p_user_id owns the room, or is a TradeTraxs admin managing an official room.';

revoke all on function public.can_manage_trade_room(uuid, uuid) from public;
grant execute on function public.can_manage_trade_room(uuid, uuid) to authenticated;

-- =============================================================================
-- 2. Official room mutation guard — allow authorized admins; block room_kind drift
-- =============================================================================

create or replace function public.rooms_room_kind_guard()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if coalesce(new.room_kind, 'community') <> 'community' then
      raise exception 'official rooms cannot be created by users'
        using errcode = '42501';
    end if;
    new.room_kind := 'community';
    new.discovery_tags := coalesce(new.discovery_tags, '{}'::text[]);
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.room_kind = 'official' then
      if not public.rate_limit_is_service_role() then
        if not public.can_manage_trade_room(old.id, auth.uid()) then
          raise exception 'official rooms are managed by TradeTraxs'
            using errcode = '42501';
        end if;
        if new.room_kind is distinct from old.room_kind then
          raise exception 'room_kind cannot be changed'
            using errcode = '42501';
        end if;
        if new.owner_user_id is distinct from old.owner_user_id then
          raise exception 'official room ownership cannot be changed'
            using errcode = '42501';
        end if;
      end if;
    elsif new.room_kind is distinct from old.room_kind then
      raise exception 'room_kind cannot be changed'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' and old.room_kind = 'official' then
    if not public.rate_limit_is_service_role() then
      raise exception 'official rooms cannot be deleted'
        using errcode = '42501';
    end if;
  end if;

  return coalesce(new, old);
end;
$$;

-- =============================================================================
-- 3. rooms UPDATE — official managers (admin + owner paths stay separate)
-- =============================================================================

drop policy if exists "rooms_update_official_manager" on public.rooms;
create policy "rooms_update_official_manager"
  on public.rooms
  for update
  to authenticated
  using (
    room_kind = 'official'
    and public.can_manage_trade_room(id, auth.uid())
  )
  with check (
    room_kind = 'official'
    and public.can_manage_trade_room(id, auth.uid())
  );

-- =============================================================================
-- 4. room_sections
-- =============================================================================

drop policy if exists "room_sections_select_member" on public.room_sections;
create policy "room_sections_select_member"
  on public.room_sections
  for select
  to authenticated
  using (
    public.is_active_room_member(room_id, auth.uid())
    or public.can_manage_trade_room(room_id, auth.uid())
  );

drop policy if exists "room_sections_insert_owner" on public.room_sections;
create policy "room_sections_insert_owner"
  on public.room_sections
  for insert
  to authenticated
  with check (public.can_manage_trade_room(room_id, auth.uid()));

drop policy if exists "room_sections_update_owner" on public.room_sections;
create policy "room_sections_update_owner"
  on public.room_sections
  for update
  to authenticated
  using (public.can_manage_trade_room(room_id, auth.uid()))
  with check (public.can_manage_trade_room(room_id, auth.uid()));

drop policy if exists "room_sections_delete_owner" on public.room_sections;
create policy "room_sections_delete_owner"
  on public.room_sections
  for delete
  to authenticated
  using (public.can_manage_trade_room(room_id, auth.uid()));

-- =============================================================================
-- 5. room_members
-- =============================================================================

drop policy if exists "room_members_select_owner" on public.room_members;
create policy "room_members_select_owner"
  on public.room_members
  for select
  to authenticated
  using (
    public.can_manage_trade_room(room_id, auth.uid())
  );

drop policy if exists "room_members_update_owner" on public.room_members;
create policy "room_members_update_owner"
  on public.room_members
  for update
  to authenticated
  using (
    public.can_manage_trade_room(room_id, auth.uid())
    and user_id <> auth.uid()
  )
  with check (
    public.can_manage_trade_room(room_id, auth.uid())
    and user_id <> auth.uid()
  );

drop policy if exists "room_members_delete_owner" on public.room_members;
create policy "room_members_delete_owner"
  on public.room_members
  for delete
  to authenticated
  using (
    public.can_manage_trade_room(room_id, auth.uid())
    and user_id <> auth.uid()
  );

-- =============================================================================
-- 6. room_messages moderation
-- =============================================================================

create or replace function public.room_messages_before_update_guard()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.user_id = auth.uid() then
    if old.pinned is distinct from new.pinned
       and not public.can_manage_trade_room(new.room_id, auth.uid()) then
      raise exception 'only room owner may change pinned';
    end if;
    return new;
  end if;

  if public.can_manage_trade_room(new.room_id, auth.uid()) then
    if old.room_id is distinct from new.room_id
       or old.user_id is distinct from new.user_id
       or old.content is distinct from new.content
       or old.image_url is distinct from new.image_url
       or old.trade_id is distinct from new.trade_id
       or old.section_id is distinct from new.section_id
       or old.type is distinct from new.type
       or old.pinned_trade_id is distinct from new.pinned_trade_id
       or old.created_at is distinct from new.created_at
    then
      raise exception 'room owner may only pin or mark seen on others'' messages';
    end if;
    return new;
  end if;

  if public.is_active_room_member(new.room_id, auth.uid()) then
    if old.room_id is distinct from new.room_id
       or old.user_id is distinct from new.user_id
       or old.content is distinct from new.content
       or old.image_url is distinct from new.image_url
       or old.trade_id is distinct from new.trade_id
       or old.section_id is distinct from new.section_id
       or old.type is distinct from new.type
       or old.pinned is distinct from new.pinned
       or old.pinned_trade_id is distinct from new.pinned_trade_id
       or old.created_at is distinct from new.created_at
    then
      raise exception 'members may only update seen_by on others'' messages';
    end if;
    return new;
  end if;

  return new;
end;
$$;

drop policy if exists "room_messages_update_owner" on public.room_messages;
create policy "room_messages_update_owner"
  on public.room_messages
  for update
  to authenticated
  using (
    public.can_manage_trade_room(room_id, auth.uid())
  )
  with check (
    public.can_manage_trade_room(room_id, auth.uid())
  );

drop policy if exists "room_messages_delete_owner" on public.room_messages;
create policy "room_messages_delete_owner"
  on public.room_messages
  for delete
  to authenticated
  using (
    public.can_manage_trade_room(room_id, auth.uid())
  );

-- =============================================================================
-- 7. room_bans
-- =============================================================================

drop policy if exists "room_bans_select_owner" on public.room_bans;
create policy "room_bans_select_owner"
  on public.room_bans
  for select
  to authenticated
  using (
    public.can_manage_trade_room(room_id, auth.uid())
  );

drop policy if exists "room_bans_insert_owner" on public.room_bans;
create policy "room_bans_insert_owner"
  on public.room_bans
  for insert
  to authenticated
  with check (
    public.can_manage_trade_room(room_id, auth.uid())
    and banned_by = auth.uid()
    and user_id <> auth.uid()
  );

drop policy if exists "room_bans_delete_owner" on public.room_bans;
create policy "room_bans_delete_owner"
  on public.room_bans
  for delete
  to authenticated
  using (
    public.can_manage_trade_room(room_id, auth.uid())
  );

-- =============================================================================
-- 8. room_member_tags + assignments
-- =============================================================================

create or replace function public.ensure_room_member_tags_defaults(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  preset_names text[] := array[
    'Admin', 'Moderator', 'Mentor', 'Verified', 'Top Trader', 'Funded',
    'Live Trader', 'Futures', 'Options', 'Crypto', 'New Member'
  ];
  preset_colors text[] := array[
    'purple', 'purple', 'blue', 'teal', 'orange', 'green',
    'green', 'blue', 'orange', 'orange', 'gray'
  ];
  i int;
begin
  if not public.can_manage_trade_room(p_room_id, auth.uid()) then
    raise exception 'not authorized to seed room member tags';
  end if;

  if exists (
    select 1 from public.room_member_tags t where t.room_id = p_room_id
  ) then
    return;
  end if;

  for i in 1..array_length(preset_names, 1) loop
    insert into public.room_member_tags (
      room_id, name, color_key, is_preset, created_by
    )
    values (
      p_room_id,
      preset_names[i],
      preset_colors[i],
      true,
      auth.uid()
    );
  end loop;
end;
$$;

drop policy if exists "room_member_tags_select_member" on public.room_member_tags;
create policy "room_member_tags_select_member"
  on public.room_member_tags
  for select
  to authenticated
  using (
    public.is_active_room_member(room_id, auth.uid())
    or public.can_manage_trade_room(room_id, auth.uid())
  );

drop policy if exists "room_member_tags_insert_owner" on public.room_member_tags;
create policy "room_member_tags_insert_owner"
  on public.room_member_tags
  for insert
  to authenticated
  with check (
    public.can_manage_trade_room(room_id, auth.uid())
    and created_by = auth.uid()
  );

drop policy if exists "room_member_tags_update_owner" on public.room_member_tags;
create policy "room_member_tags_update_owner"
  on public.room_member_tags
  for update
  to authenticated
  using (public.can_manage_trade_room(room_id, auth.uid()))
  with check (public.can_manage_trade_room(room_id, auth.uid()));

drop policy if exists "room_member_tags_delete_owner" on public.room_member_tags;
create policy "room_member_tags_delete_owner"
  on public.room_member_tags
  for delete
  to authenticated
  using (public.can_manage_trade_room(room_id, auth.uid()));

drop policy if exists "room_member_tag_assignments_select_member" on public.room_member_tag_assignments;
create policy "room_member_tag_assignments_select_member"
  on public.room_member_tag_assignments
  for select
  to authenticated
  using (
    public.is_active_room_member(room_id, auth.uid())
    or public.can_manage_trade_room(room_id, auth.uid())
  );

drop policy if exists "room_member_tag_assignments_insert_owner" on public.room_member_tag_assignments;
create policy "room_member_tag_assignments_insert_owner"
  on public.room_member_tag_assignments
  for insert
  to authenticated
  with check (
    public.can_manage_trade_room(room_id, auth.uid())
    and exists (
      select 1
      from public.room_members m
      where m.room_id = room_member_tag_assignments.room_id
        and m.user_id = room_member_tag_assignments.user_id
        and m.left_at is null
    )
    and exists (
      select 1
      from public.room_member_tags t
      where t.id = room_member_tag_assignments.tag_id
        and t.room_id = room_member_tag_assignments.room_id
    )
  );

drop policy if exists "room_member_tag_assignments_delete_owner" on public.room_member_tag_assignments;
create policy "room_member_tag_assignments_delete_owner"
  on public.room_member_tag_assignments
  for delete
  to authenticated
  using (public.can_manage_trade_room(room_id, auth.uid()));

-- =============================================================================
-- 9. room_join_requests
-- =============================================================================

drop policy if exists "room_join_requests_select_participant" on public.room_join_requests;
create policy "room_join_requests_select_participant"
  on public.room_join_requests
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or public.can_manage_trade_room(room_id, auth.uid())
  );

drop policy if exists "room_join_requests_update_owner" on public.room_join_requests;
create policy "room_join_requests_update_owner"
  on public.room_join_requests
  for update
  to authenticated
  using (public.can_manage_trade_room(room_id, auth.uid()))
  with check (public.can_manage_trade_room(room_id, auth.uid()));

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

  if not public.can_manage_trade_room(p_room_id, v_uid) then
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

  if not public.can_manage_trade_room(v_request.room_id, v_uid) then
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

  update public.room_join_requests
  set status = 'approved',
      resolved_at = timezone('utc', now()),
      resolved_by = v_uid
  where id = v_request.id
  returning * into v_request;

  insert into public.room_members (room_id, user_id, notification_enabled, left_at)
  values (v_request.room_id, v_request.user_id, true, null)
  on conflict do nothing;

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

grant execute on function public.rpc_v1_list_trade_room_join_requests(uuid, text) to authenticated;
grant execute on function public.rpc_v1_resolve_trade_room_join_request(uuid, text) to authenticated;

-- =============================================================================
-- 10. Storage — room image uploads (avatars bucket, room-images/ prefix)
-- =============================================================================

drop policy if exists "avatars_storage_insert_room_images" on storage.objects;
create policy "avatars_storage_insert_room_images"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = 'room-images'
  );

drop policy if exists "avatars_storage_update_room_images" on storage.objects;
create policy "avatars_storage_update_room_images"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = 'room-images'
  );
