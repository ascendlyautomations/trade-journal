-- Single source of truth for the iOS app-icon badge:
-- Activity inbox unread + unmuted DM unread (rooms excluded — matches product policy).

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
  -- Authenticated callers may only read their own badge.
  if v_caller is not null then
    if p_user_id is not null and p_user_id <> v_caller then
      raise exception 'badge_forbidden' using errcode = '42501';
    end if;
    v_uid := v_caller;
  else
    -- service_role (no auth.uid) must pass the recipient explicitly.
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

comment on function public.get_app_icon_badge(uuid) is
  'App icon badge = Activity inbox unread + unmuted DM unread. Rooms excluded.';

revoke all on function public.get_app_icon_badge(uuid) from public;
grant execute on function public.get_app_icon_badge(uuid) to authenticated;
grant execute on function public.get_app_icon_badge(uuid) to service_role;
