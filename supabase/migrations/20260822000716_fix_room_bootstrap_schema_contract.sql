-- Phase F regression fix: rpc_v1_room_bootstrap referenced non-existent rooms columns.
-- Real public.rooms columns (from migrations + loadMemberRooms):
--   id, name, description, slug, image_url, owner_user_id, show_on_profile
-- Removed invalid references: is_public, allow_members_chat (dropped from rooms), created_at

create or replace function public.rpc_v1_room_bootstrap(
  p_room_id uuid,
  p_section_id uuid default null,
  p_message_limit integer default 25,
  p_mark_read boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_message_limit, 25), 50));
  v_room record;
  v_member record;
  v_sections jsonb := '[]'::jsonb;
  v_section_count integer := 0;
  v_active_section_id uuid;
  v_active_section_name text;
  v_channel_prefs jsonb := '{}'::jsonb;
  v_pinned jsonb := '[]'::jsonb;
  v_messages jsonb := '[]'::jsonb;
  v_has_more boolean := false;
  v_next_cursor text := null;
  v_unread bigint := 0;
  v_mark_applied boolean := false;
  v_total_members bigint := null;
  v_active_members bigint := null;
  v_is_owner boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_room_id is null then
    raise exception 'room_id_required' using errcode = '22023';
  end if;

  select
    rm.notification_enabled,
    rm.last_read_at,
    rm.last_read_message_id,
    rm.left_at
  into v_member
  from public.room_members rm
  where rm.room_id = p_room_id
    and rm.user_id = v_uid;

  if not found or v_member.left_at is not null then
    raise exception 'room_access_denied' using errcode = '42501';
  end if;

  select
    r.id,
    r.name,
    r.description,
    r.slug,
    r.image_url,
    r.owner_user_id,
    r.show_on_profile
  into v_room
  from public.rooms r
  where r.id = p_room_id;

  if not found then
    raise exception 'room_not_found' using errcode = 'P0002';
  end if;

  v_is_owner := v_room.owner_user_id = v_uid;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', s.id,
        'room_id', s.room_id,
        'name', s.name,
        'position', s.position,
        'allow_members_chat', coalesce(s.allow_members_chat, true)
      )
      order by s.position asc, s.id asc
    ),
    '[]'::jsonb
  )
  into v_sections
  from public.room_sections s
  where s.room_id = p_room_id;

  v_section_count := jsonb_array_length(v_sections);

  if v_section_count > 0 then
    if p_section_id is not null
       and exists (
         select 1
         from public.room_sections s2
         where s2.room_id = p_room_id and s2.id = p_section_id
       ) then
      v_active_section_id := p_section_id;
    else
      select s3.id, s3.name
      into v_active_section_id, v_active_section_name
      from public.room_sections s3
      where s3.room_id = p_room_id
      order by s3.position asc, s3.id asc
      limit 1;
    end if;

    if v_active_section_name is null then
      select s4.name
      into v_active_section_name
      from public.room_sections s4
      where s4.id = v_active_section_id;
    end if;
  end if;

  if v_section_count > 0 then
    select coalesce(
      jsonb_object_agg(
        cp.section_id::text,
        (cp.notifications_enabled is distinct from false)
      ),
      '{}'::jsonb
    )
    into v_channel_prefs
    from public.room_member_channel_preferences cp
    where cp.user_id = v_uid
      and cp.room_id = p_room_id
      and cp.section_id in (
        select (elem->>'id')::uuid
        from jsonb_array_elements(v_sections) elem
      );
  end if;

  if v_is_owner then
    select
      count(*)::bigint,
      count(*) filter (where rm.left_at is null)::bigint
    into v_total_members, v_active_members
    from public.room_members rm
    where rm.room_id = p_room_id;
  end if;

  if p_mark_read then
    perform public.mark_room_read(p_room_id);
    v_mark_applied := true;
  end if;

  select coalesce(u.unread_count, 0)
  into v_unread
  from public.get_room_unread_counts(array[p_room_id]::uuid[]) u
  where u.room_id = p_room_id;

  with filtered as (
    select msg.id, msg.created_at
    from public.room_messages msg
    where msg.room_id = p_room_id
      and msg.pinned = true
      and (
        v_section_count = 0
        or (
          v_active_section_id is not null
          and (
            (
              lower(trim(coalesce(v_active_section_name, ''))) = 'general'
              and (msg.section_id = v_active_section_id or msg.section_id is null)
            )
            or (
              lower(trim(coalesce(v_active_section_name, ''))) <> 'general'
              and msg.section_id = v_active_section_id
            )
          )
        )
      )
    order by msg.created_at desc, msg.id desc
    limit 100
  )
  select coalesce(
    jsonb_agg(
      public.rpc_v1_room_bootstrap_message_row(f.id)
      order by f.created_at asc, f.id asc
    ),
    '[]'::jsonb
  )
  into v_pinned
  from filtered f;

  with filtered as (
    select msg.id, msg.created_at
    from public.room_messages msg
    where msg.room_id = p_room_id
      and msg.pinned = false
      and (
        v_section_count = 0
        or (
          v_active_section_id is not null
          and (
            (
              lower(trim(coalesce(v_active_section_name, ''))) = 'general'
              and (msg.section_id = v_active_section_id or msg.section_id is null)
            )
            or (
              lower(trim(coalesce(v_active_section_name, ''))) <> 'general'
              and msg.section_id = v_active_section_id
            )
          )
        )
      )
    order by msg.created_at desc, msg.id desc
    limit (v_limit + 1)
  ),
  page_ids as (
    select f.id, f.created_at
    from filtered f
    order by f.created_at desc, f.id desc
    limit v_limit
  )
  select
    coalesce(
      (
        select jsonb_agg(
          public.rpc_v1_room_bootstrap_message_row(p.id)
          order by p.created_at asc, p.id asc
        )
        from page_ids p
      ),
      '[]'::jsonb
    ),
    (select count(*) > v_limit from filtered),
    (
      select
        to_char(timezone('utc', oldest.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        || '|'
        || oldest.id::text
      from (
        select p2.created_at, p2.id
        from page_ids p2
        order by p2.created_at asc, p2.id asc
        limit 1
      ) oldest
    )
  into v_messages, v_has_more, v_next_cursor;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'room', jsonb_build_object(
        'id', v_room.id,
        'name', v_room.name,
        'description', v_room.description,
        'slug', v_room.slug,
        'image_url', v_room.image_url,
        'owner_user_id', v_room.owner_user_id,
        'show_on_profile', coalesce(v_room.show_on_profile, true)
      ),
      'membership', jsonb_build_object(
        'notification_enabled', (v_member.notification_enabled is distinct from false),
        'is_owner', v_is_owner
      ),
      'sections', v_sections,
      'active_section_id', v_active_section_id,
      'channel_preferences', coalesce(v_channel_prefs, '{}'::jsonb),
      'member_stats', case
        when v_is_owner then jsonb_build_object(
          'total_members', coalesce(v_total_members, 0),
          'active_members', coalesce(v_active_members, 0),
          'left_members', greatest(coalesce(v_total_members, 0) - coalesce(v_active_members, 0), 0)
        )
        else null
      end,
      'unread_count', coalesce(v_unread, 0),
      'mark_read', jsonb_build_object('applied', v_mark_applied),
      'pinned_messages', v_pinned,
      'messages', v_messages,
      'has_more_messages', coalesce(v_has_more, false),
      'next_message_cursor', v_next_cursor
    )
  );
end;
$$;

revoke all on function public.rpc_v1_room_bootstrap(uuid, uuid, integer, boolean) from public;
grant execute on function public.rpc_v1_room_bootstrap(uuid, uuid, integer, boolean) to authenticated;

comment on function public.rpc_v1_room_bootstrap is
  'Phase F: bounded Trade Room bootstrap — schema-correct rooms projection.';
