-- Phase G: Personal conversation thread bootstrap — single bounded JSON for thread open / pagination.
-- VOLATILE: may perform mark_conversation_read when p_mark_read = true.
-- Does not modify rpc_v2_messaging_bootstrap (inbox).

create or replace function public.rpc_v1_conversation_thread_message_row(p_message_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'id', m.id,
    'conversation_id', m.conversation_id,
    'sender_id', m.sender_id,
    'sender_anonymized', coalesce(m.sender_anonymized, false),
    'content', m.content,
    'created_at', case
      when m.created_at is null then null
      else to_char(timezone('utc', m.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    end,
    'seen_by', coalesce(m.seen_by, '{}'::uuid[]),
    'type', m.type,
    'trade_id', m.trade_id,
    'post_id', m.post_id,
    'profile_post_id', m.profile_post_id,
    'achievement_post_id', m.achievement_post_id,
    'reel_id', m.reel_id,
    'parent_message_id', m.parent_message_id,
    'deleted_for_everyone', coalesce(m.deleted_for_everyone, false),
    'image_url', m.image_url,
    'is_system', coalesce(m.is_system, false),
    'profiles', case
      when m.sender_id is null then null
      else (
        select jsonb_build_object(
          'username', pr.username,
          'avatar_url', pr.avatar_url
        )
        from public.profiles pr
        where pr.id = m.sender_id
      )
    end
  )
  from public.messages m
  where m.id = p_message_id;
$$;

revoke all on function public.rpc_v1_conversation_thread_message_row(uuid) from public;
grant execute on function public.rpc_v1_conversation_thread_message_row(uuid) to authenticated;

create or replace function public.rpc_v1_conversation_thread_bootstrap(
  p_conversation_id uuid,
  p_message_limit integer default 50,
  p_cursor text default null,
  p_mark_read boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := (select auth.uid());
  v_limit integer := greatest(1, least(coalesce(p_message_limit, 50), 80));
  v_cursor_ts timestamptz;
  v_cursor_id uuid;
  v_cursor_legacy boolean := true;
  v_convo record;
  v_notifications_enabled boolean := true;
  v_participants jsonb := '[]'::jsonb;
  v_messages jsonb := '[]'::jsonb;
  v_has_more boolean := false;
  v_next_cursor text := null;
  v_mark_applied boolean := false;
  v_notifications_marked integer := 0;
  v_unread_count integer := 0;
  v_block jsonb := null;
  v_other_user_id uuid := null;
  v_blocked_by_me boolean := false;
  v_blocked_by_other boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_conversation_id is null then
    raise exception 'conversation_id_required' using errcode = '22023';
  end if;

  if not public.is_conversation_participant(p_conversation_id, v_uid) then
    raise exception 'conversation_access_denied' using errcode = '42501';
  end if;

  select c.id, c.is_group, c.name, c.avatar_url, c.is_pinned
  into v_convo
  from public.conversations c
  where c.id = p_conversation_id;

  if not found then
    raise exception 'conversation_not_found' using errcode = 'P0002';
  end if;

  select cmp.notifications_enabled
  into v_notifications_enabled
  from public.conversation_member_preferences cmp
  where cmp.user_id = v_uid
    and cmp.conversation_id = p_conversation_id;

  if not found then
    v_notifications_enabled := true;
  else
    v_notifications_enabled := v_notifications_enabled is distinct from false;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'user_id', cp.user_id,
        'profiles', jsonb_build_object(
          'id', pr.id,
          'username', pr.username,
          'avatar_url', pr.avatar_url
        )
      )
      order by cp.user_id asc
    ),
    '[]'::jsonb
  )
  into v_participants
  from public.conversation_participants cp
  join public.profiles pr on pr.id = cp.user_id
  where cp.conversation_id = p_conversation_id;

  if coalesce(v_convo.is_group, false) = false then
    select cp.user_id
    into v_other_user_id
    from public.conversation_participants cp
    where cp.conversation_id = p_conversation_id
      and cp.user_id <> v_uid
    limit 1;

    if v_other_user_id is not null then
      select
        coalesce(s.blocked_by_me, false),
        coalesce(s.blocked_by_other, false)
      into v_blocked_by_me, v_blocked_by_other
      from public.get_dm_block_status(p_conversation_id) s
      limit 1;

      v_block := jsonb_build_object(
        'other_user_id', v_other_user_id::text,
        'blocked_by_me', v_blocked_by_me,
        'blocked_by_other', v_blocked_by_other
      );
    end if;
  end if;

  select c.cursor_ts, c.cursor_id, c.legacy_only
  into v_cursor_ts, v_cursor_id, v_cursor_legacy
  from public._v2_messaging_parse_cursor(p_cursor) c;

  with visible as (
    select m.id, m.created_at
    from public.messages m
    where m.conversation_id = p_conversation_id
      and (
        coalesce(m.deleted_for_everyone, false) = true
        or not exists (
          select 1
          from public.message_deletions md
          where md.message_id = m.id
            and md.user_id = v_uid
        )
      )
      and public._v2_messaging_before_cursor(
        m.created_at,
        m.id,
        v_cursor_ts,
        v_cursor_id,
        v_cursor_legacy
      )
    order by m.created_at desc, m.id desc
    limit (v_limit + 1)
  ),
  page_ids as (
    select v.id, v.created_at
    from visible v
    order by v.created_at desc, v.id desc
    limit v_limit
  )
  select
    coalesce(
      (
        select jsonb_agg(
          public.rpc_v1_conversation_thread_message_row(p.id)
          order by p.created_at asc, p.id asc
        )
        from page_ids p
      ),
      '[]'::jsonb
    ),
    (select count(*) > v_limit from visible),
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

  if p_mark_read then
    perform public.mark_conversation_read(p_conversation_id);
    v_mark_applied := true;

    update public.notifications n
    set read = true
    where n.user_id = v_uid
      and n.type = 'message'
      and n.read = false
      and n.content ilike ('%' || p_conversation_id::text || '%');
    get diagnostics v_notifications_marked = row_count;
  end if;

  select coalesce(u.unread_count, 0)
  into v_unread_count
  from public.get_conversation_unread_counts(array[p_conversation_id]::uuid[]) u
  where u.conversation_id = p_conversation_id;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'conversation', jsonb_build_object(
        'id', v_convo.id,
        'is_group', coalesce(v_convo.is_group, false),
        'name', v_convo.name,
        'avatar_url', v_convo.avatar_url,
        'is_pinned', coalesce(v_convo.is_pinned, false)
      ),
      'membership', jsonb_build_object(
        'is_participant', true
      ),
      'participants', v_participants,
      'notifications_enabled', v_notifications_enabled,
      'block_status', v_block,
      'messages', v_messages,
      'has_more_messages', v_has_more,
      'next_message_cursor', v_next_cursor,
      'unread_count', v_unread_count,
      'mark_read', jsonb_build_object(
        'applied', v_mark_applied
      ),
      'notifications_marked_read', v_notifications_marked,
      'page_meta', jsonb_build_object(
        'limit', v_limit,
        'returned', jsonb_array_length(v_messages),
        'has_more', v_has_more
      )
    )
  );
end;
$$;

revoke all on function public.rpc_v1_conversation_thread_bootstrap(uuid, integer, text, boolean) from public;
grant execute on function public.rpc_v1_conversation_thread_bootstrap(uuid, integer, text, boolean) to authenticated;

comment on function public.rpc_v1_conversation_thread_bootstrap is
  'Phase G: bounded personal/group conversation thread bootstrap — metadata, participants, messages, optional mark_read.';
