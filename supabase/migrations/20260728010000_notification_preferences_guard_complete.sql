-- Align should_deliver_notification with Settings preference keys.
-- Fixes gaps: room_mention, follow_request_accepted, like batches/milestones,
-- trading reports (product_updates), and keeps master switch authoritative.

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

  -- Missing row → deliver (defaults are all enabled; trigger backfills new profiles).
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
      -- Reply / mention / top-level kinds are enforced in the API route.
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
    when 'message' then
      return prefs.direct_messages_enabled;
    when 'trading_report' then
      return prefs.product_updates_enabled;
    when 'affiliate_referral' then
      -- No dedicated Settings toggle yet — master switch only.
      return true;
    when 'affiliate_commission_earned' then
      return true;
    else
      return true;
  end case;
end;
$$;

comment on function public.should_deliver_notification(uuid, text, uuid) is
  'Central preference guard for notifications INSERT. Mirrors Settings toggles.';
