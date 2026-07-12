-- Allow service_role to anonymize DM senders during account deletion.
-- Root cause: messages_before_update_guard required conversation participation via
-- auth.uid(), which is NULL for the service role, so admin/self-service deletion
-- failed with: raise exception 'not a conversation participant'

create or replace function public.messages_before_update_guard()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.parent_message_id is distinct from new.parent_message_id then
    raise exception 'parent_message_id is immutable';
  end if;

  if old.type is distinct from new.type then
    raise exception 'message type is immutable'
      using errcode = '42501';
  end if;

  if old.trade_id is distinct from new.trade_id then
    raise exception 'trade_id is immutable'
      using errcode = '42501';
  end if;

  -- Account deletion (service role): preserve DM rows; clear sender identity only.
  -- Matches deleteUserAdmin anonymizeUserDirectMessages():
  --   sender_anonymized = true, sender_id = null, user_id = null
  if auth.role() = 'service_role'
     and new.conversation_id is not null
     and coalesce(new.sender_anonymized, false) = true
     and new.sender_id is null
  then
    return new;
  end if;

  -- Public lobby rows (channel-based): author-only updates; no seen_by path.
  if new.channel is not null then
    if old.user_id is distinct from auth.uid() then
      raise exception 'lobby messages may only be updated by author';
    end if;
    return new;
  end if;

  -- Conversation messages.
  if new.conversation_id is null then
    return new;
  end if;

  if not public.is_conversation_participant(new.conversation_id, auth.uid()) then
    raise exception 'not a conversation participant';
  end if;

  -- Sender may update own conversation message (e.g. deleted_for_everyone).
  if old.sender_id = auth.uid() then
    return new;
  end if;

  -- System messages (sender_id null): participants may only update seen_by.
  if old.sender_id is null then
    if old.conversation_id is distinct from new.conversation_id
       or old.sender_id is distinct from new.sender_id
       or old.content is distinct from new.content
       or old.image_url is distinct from new.image_url
       or old.is_system is distinct from new.is_system
       or old.deleted_for_everyone is distinct from new.deleted_for_everyone
       or old.created_at is distinct from new.created_at
       or old.channel is distinct from new.channel
       or old.user_id is distinct from new.user_id
    then
      raise exception 'participants may only update seen_by on system messages';
    end if;
    return new;
  end if;

  -- Participants may only update seen_by on someone else's message.
  if old.conversation_id is distinct from new.conversation_id
     or old.sender_id is distinct from new.sender_id
     or old.content is distinct from new.content
     or old.image_url is distinct from new.image_url
     or old.is_system is distinct from new.is_system
     or old.deleted_for_everyone is distinct from new.deleted_for_everyone
     or old.created_at is distinct from new.created_at
     or old.channel is distinct from new.channel
     or old.user_id is distinct from new.user_id
  then
    raise exception 'participants may only update seen_by on others'' messages';
  end if;

  return new;
end;
$$;

comment on function public.messages_before_update_guard() is
  'Guards messages UPDATEs. Service role may anonymize conversation senders for account deletion.';
