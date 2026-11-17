-- When a sub-room has allow_members_chat = false, room owners and members with the
-- Moderator tag may post; regular members may not.

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
      if not public.has_room_moderator_tag(p_room_id, p_user_id) then
        return false;
      end if;
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