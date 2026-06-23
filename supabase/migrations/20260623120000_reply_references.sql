-- Lightweight reply references (single parent, no thread nesting).

alter table public.room_messages
  add column if not exists parent_message_id uuid null
    references public.room_messages (id) on delete set null;

alter table public.messages
  add column if not exists parent_message_id uuid null
    references public.messages (id) on delete set null;

alter table public.comments
  add column if not exists parent_comment_id uuid null
    references public.comments (id) on delete set null;

alter table public.trade_comments
  add column if not exists parent_comment_id uuid null
    references public.trade_comments (id) on delete set null;

create index if not exists room_messages_parent_message_id_idx
  on public.room_messages (parent_message_id)
  where parent_message_id is not null;

create index if not exists messages_parent_message_id_idx
  on public.messages (parent_message_id)
  where parent_message_id is not null;

create index if not exists comments_parent_comment_id_idx
  on public.comments (parent_comment_id)
  where parent_comment_id is not null;

create index if not exists trade_comments_parent_comment_id_idx
  on public.trade_comments (parent_comment_id)
  where parent_comment_id is not null;

comment on column public.room_messages.parent_message_id is
  'Optional reply reference to another room message (one level, not a thread tree).';
comment on column public.messages.parent_message_id is
  'Optional reply reference to another DM message (one level, not a thread tree).';
comment on column public.comments.parent_comment_id is
  'Optional reply reference to another feed post comment (flat list).';
comment on column public.trade_comments.parent_comment_id is
  'Optional reply reference to another trade comment (flat list).';

-- parent_message_id is set on insert only
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

  if old.parent_message_id is distinct from new.parent_message_id then
    raise exception 'parent_message_id is immutable';
  end if;

  if old.user_id = auth.uid() then
    if old.pinned is distinct from new.pinned
       and not public.is_room_owner(new.room_id, auth.uid()) then
      raise exception 'only room owner may change pinned';
    end if;
    return new;
  end if;

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

  -- Participants may only update seen_by on someone else''s message.
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
