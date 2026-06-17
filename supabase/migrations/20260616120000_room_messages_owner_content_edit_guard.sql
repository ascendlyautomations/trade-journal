-- Restrict room owners to pin/seen_by updates on others' messages (not content edits).

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

  -- Author may update own message content/fields; pinned changes require owner.
  if old.user_id = auth.uid() then
    if old.pinned is distinct from new.pinned
       and not public.is_room_owner(new.room_id, auth.uid()) then
      raise exception 'only room owner may change pinned';
    end if;
    return new;
  end if;

  -- Room owner moderation on others' messages: pin / seen_by only.
  if public.is_room_owner(new.room_id, auth.uid()) then
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

  -- Active members may only mutate seen_by on someone else's message.
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
