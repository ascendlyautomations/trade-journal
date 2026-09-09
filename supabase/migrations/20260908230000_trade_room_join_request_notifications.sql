-- Trade Room join-request notifications — Activity inbox, badge, and detail RPC.

-- =============================================================================
-- 1. Recipients who may approve join requests for a room
-- =============================================================================

create or replace function public.trade_room_join_request_recipient_ids(p_room_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select distinct recipient_id
  from (
    select r.owner_user_id as recipient_id
    from public.rooms r
    where r.id = p_room_id
      and r.owner_user_id is not null

    union all

    select au.user_id as recipient_id
    from public.rooms r
    inner join public.admin_users au on true
    where r.id = p_room_id
      and r.room_kind = 'official'
  ) recipients
  where recipient_id is not null;
$$;

comment on function public.trade_room_join_request_recipient_ids(uuid) is
  'Users who may approve join requests: room owner (community) or platform admins (official).';

revoke all on function public.trade_room_join_request_recipient_ids(uuid) from public;
grant execute on function public.trade_room_join_request_recipient_ids(uuid) to authenticated;
grant execute on function public.trade_room_join_request_recipient_ids(uuid) to service_role;

-- =============================================================================
-- 2. Detail RPC for Activity / deep-link destination (authoritative status)
-- =============================================================================

create or replace function public.rpc_v1_trade_room_join_request_detail(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_request public.room_join_requests%rowtype;
  v_room record;
  v_requester record;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_request_id is null then
    raise exception 'request_id_required' using errcode = '22023';
  end if;

  select * into v_request
  from public.room_join_requests
  where id = p_request_id;

  if not found then
    raise exception 'request_not_found' using errcode = 'P0002';
  end if;

  if v_request.user_id <> v_uid
     and not public.can_manage_trade_room(v_request.room_id, v_uid) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select
    r.id,
    r.name,
    r.slug,
    r.image_url,
    r.room_kind,
    r.owner_user_id
  into v_room
  from public.rooms r
  where r.id = v_request.room_id;

  select
    p.id,
    p.username,
    p.name,
    p.avatar_url
  into v_requester
  from public.profiles p
  where p.id = v_request.user_id;

  return jsonb_build_object(
    'id', v_request.id,
    'room_id', v_request.room_id,
    'user_id', v_request.user_id,
    'status', v_request.status,
    'created_at', v_request.created_at,
    'resolved_at', v_request.resolved_at,
    'can_resolve',
      public.can_manage_trade_room(v_request.room_id, v_uid)
      and v_request.status = 'pending',
    'room', jsonb_build_object(
      'id', v_room.id,
      'name', v_room.name,
      'slug', v_room.slug,
      'image_url', v_room.image_url,
      'room_kind', v_room.room_kind
    ),
    'requester', jsonb_build_object(
      'id', v_requester.id,
      'username', v_requester.username,
      'name', v_requester.name,
      'avatar_url', v_requester.avatar_url
    )
  );
end;
$$;

grant execute on function public.rpc_v1_trade_room_join_request_detail(uuid) to authenticated;

-- =============================================================================
-- 3. Sync Activity rows when a join request is resolved
-- =============================================================================

create or replace function public.sync_trade_room_join_request_notifications(
  p_request_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_request_id is null or p_status is null then
    return;
  end if;

  update public.notifications n
  set content = (
    coalesce(nullif(trim(n.content), ''), '{}')::jsonb
    || jsonb_build_object('request_status', p_status)
  )::text
  where n.type = 'trade_room_join_request'
    and n.content is not null
    and n.content ~ '^\s*\{'
    and (n.content::jsonb ->> 'join_request_id') = p_request_id::text;
end;
$$;

revoke all on function public.sync_trade_room_join_request_notifications(uuid, text) from public;
grant execute on function public.sync_trade_room_join_request_notifications(uuid, text) to service_role;

-- =============================================================================
-- 4. Dedupe — one inbox row per approver / requester / room
-- =============================================================================

create unique index if not exists notifications_trade_room_join_request_unique_idx
  on public.notifications (user_id, sender_id, room_id)
  where type = 'trade_room_join_request'
    and room_id is not null;

create unique index if not exists notifications_trade_room_join_accepted_unique_idx
  on public.notifications (user_id, room_id)
  where type = 'trade_room_join_accepted';

create unique index if not exists notifications_trade_room_join_declined_unique_idx
  on public.notifications (user_id, room_id)
  where type = 'trade_room_join_declined';

-- =============================================================================
-- 5. Preference guard + Activity inbox + badge
-- =============================================================================

create or replace function public.should_deliver_notification(
  p_recipient_id uuid,
  p_type text,
  p_achievement_post_id uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  prefs public.notification_preferences%rowtype;
begin
  if p_recipient_id is null then
    return false;
  end if;

  select * into prefs
  from public.notification_preferences
  where user_id = p_recipient_id;

  if not found then
    return true;
  end if;

  if not prefs.notifications_enabled then
    return false;
  end if;

  case p_type
    when 'like' then
      if p_achievement_post_id is not null then
        return prefs.achievement_likes_enabled;
      end if;
      return prefs.likes_enabled;
    when 'like_batch' then
      if p_achievement_post_id is not null then
        return prefs.achievement_likes_enabled;
      end if;
      return prefs.likes_enabled;
    when 'like_milestone' then
      if p_achievement_post_id is not null then
        return prefs.achievement_likes_enabled;
      end if;
      return prefs.likes_enabled;
    when 'comment' then
      if p_achievement_post_id is not null then
        return prefs.achievement_comments_enabled;
      end if;
      return true;
    when 'follow' then
      return prefs.followers_enabled;
    when 'follow_batch' then
      return prefs.followers_enabled;
    when 'follow_request' then
      return prefs.follow_requests_enabled;
    when 'follow_request_accepted' then
      return prefs.follow_request_accepts_enabled;
    when 'room_message' then
      return prefs.room_messages_enabled;
    when 'room_mention' then
      return prefs.room_mentions_enabled;
    when 'room_join' then
      return prefs.room_joins_enabled;
    when 'trade_room_join_request' then
      return prefs.room_joins_enabled;
    when 'trade_room_join_accepted' then
      return prefs.room_joins_enabled;
    when 'trade_room_join_declined' then
      return prefs.room_joins_enabled;
    when 'message' then
      return prefs.direct_messages_enabled;
    when 'trading_report' then
      return prefs.product_updates_enabled;
    when 'affiliate_referral' then
      return true;
    when 'affiliate_commission_earned' then
      return true;
    else
      return true;
  end case;
end;
$$;

create or replace function public.get_app_icon_badge(
  p_user_id uuid default null
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_uid uuid;
  v_activity integer := 0;
  v_dm integer := 0;
begin
  if v_caller is not null then
    if p_user_id is not null and p_user_id <> v_caller then
      raise exception 'badge_forbidden' using errcode = '42501';
    end if;
    v_uid := v_caller;
  else
    if p_user_id is null then
      return 0;
    end if;
    v_uid := p_user_id;
  end if;

  select count(*)::integer
  into v_activity
  from public.notifications n
  where n.user_id = v_uid
    and n.read = false
    and n.type in (
      'like',
      'comment',
      'room_join',
      'room_mention',
      'follow',
      'follow_request',
      'follow_request_accepted',
      'trade_room_join_request',
      'trade_room_join_accepted',
      'trade_room_join_declined',
      'affiliate_referral',
      'affiliate_commission_earned',
      'trading_report'
    );

  select coalesce(sum(c.cnt), 0)::integer
  into v_dm
  from (
    select count(m.id)::integer as cnt
    from public.conversation_participants cp
    left join public.conversation_member_preferences prefs
      on prefs.user_id = cp.user_id
     and prefs.conversation_id = cp.conversation_id
    left join public.messages m
      on m.conversation_id = cp.conversation_id
     and m.sender_id is not null
     and m.sender_id <> cp.user_id
     and (
       prefs.last_read_at is null
       or m.created_at > prefs.last_read_at
     )
    where cp.user_id = v_uid
      and coalesce(prefs.notifications_enabled, true) = true
    group by cp.conversation_id
  ) c;

  return greatest(0, coalesce(v_activity, 0) + coalesce(v_dm, 0));
end;
$$;

-- Extend Activity inbox allowlist (full function body preserved from 20260831200000).
create or replace function public.rpc_v1_activity_bootstrap(
  p_limit int default 40,
  p_cursor timestamptz default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_limit int := greatest(least(coalesce(p_limit, 40), 100), 0);
  v_notifications jsonb := '[]'::jsonb;
  v_follow_requests jsonb := '[]'::jsonb;
  v_actors jsonb := '{}'::jsonb;
  v_unread int := 0;
  v_next_cursor text := null;
  v_inbox_types text[] := array[
    'like', 'comment', 'room_join', 'room_mention', 'follow',
    'follow_request', 'follow_request_accepted',
    'trade_room_join_request', 'trade_room_join_accepted', 'trade_room_join_declined',
    'affiliate_referral', 'affiliate_commission_earned', 'trading_report'
  ];
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select count(*)::int
  into v_unread
  from public.notifications n
  where n.user_id = v_uid
    and coalesce(n.read, false) = false
    and n.type = any (v_inbox_types);

  if v_limit > 0 then
    with page as (
      select
        n.id,
        n.user_id,
        n.sender_id,
        n.type,
        n.post_id,
        n.trade_id,
        n.profile_post_id,
        n.achievement_post_id,
        n.reel_id,
        n.comment_id,
        n.room_id,
        n.room_message_id,
        n.content,
        n.read,
        n.created_at
      from public.notifications n
      where n.user_id = v_uid
        and n.type = any (v_inbox_types)
        and (p_cursor is null or n.created_at < p_cursor)
      order by n.created_at desc
      limit v_limit + 1
    ),
    trimmed as (
      select * from page
      order by created_at desc
      limit v_limit
    ),
    meta as (
      select count(*) as cnt from page
    )
    select
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', t.id,
              'user_id', t.user_id,
              'sender_id', t.sender_id,
              'type', t.type,
              'post_id', t.post_id,
              'trade_id', t.trade_id,
              'profile_post_id', t.profile_post_id,
              'achievement_post_id', t.achievement_post_id,
              'reel_id', t.reel_id,
              'comment_id', t.comment_id,
              'room_id', t.room_id,
              'room_message_id', t.room_message_id,
              'content', t.content,
              'read', coalesce(t.read, false),
              'created_at', to_char(t.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
            )
            order by t.created_at desc
          )
          from trimmed t
        ),
        '[]'::jsonb
      ),
      case
        when (select cnt from meta) > v_limit then (
          select to_char(min(t.created_at) at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          from trimmed t
        )
        else null
      end
    into v_notifications, v_next_cursor;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', fr.id,
        'requester_id', fr.requester_id,
        'created_at', to_char(fr.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      )
      order by fr.created_at desc
    ),
    '[]'::jsonb
  )
  into v_follow_requests
  from public.follow_requests fr
  where fr.target_id = v_uid
    and fr.status = 'pending';

  with actor_ids as (
    select distinct sender_id as profile_id
    from public.notifications n
    where n.user_id = v_uid
      and n.type = any (v_inbox_types)
      and n.sender_id is not null
    union
    select fr.requester_id
    from public.follow_requests fr
    where fr.target_id = v_uid
      and fr.status = 'pending'
  )
  select coalesce(
    jsonb_object_agg(
      p.id::text,
      jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'display_name', p.name,
        'avatar_url', p.avatar_url
      )
    ),
    '{}'::jsonb
  )
  into v_actors
  from actor_ids a
  join public.profiles p on p.id = a.profile_id;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'notifications', v_notifications,
      'actors', v_actors,
      'follow_requests', v_follow_requests,
      'unread_total', v_unread,
      'next_cursor', v_next_cursor
    )
  );
end;
$$;
