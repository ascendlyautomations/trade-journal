-- Phase 2: Activity inbox bootstrap — notifications page + unread + follow requests + actors.

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

revoke all on function public.rpc_v1_activity_bootstrap(int, timestamptz) from public;
grant execute on function public.rpc_v1_activity_bootstrap(int, timestamptz) to authenticated;

comment on function public.rpc_v1_activity_bootstrap is
  'Phase 2 Activity bootstrap — inbox notifications, unread count, pending follow requests, actor cards.';
