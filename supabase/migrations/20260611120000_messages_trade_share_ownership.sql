-- P0: Enforce trade-share ownership on public.messages at the database layer.
-- Prerequisite: 20260609150000_messaging_secure_rls.sql, 20260609120000_trades_secure_rls.sql
--
-- INSERT: type = 'trade' requires trade_id owned by auth.uid(); trade_id only on type = 'trade'.
-- UPDATE: type and trade_id are immutable after insert (blocks repointing shares).

-- =============================================================================
-- 1. Shared validation helper
-- =============================================================================

create or replace function public.messages_assert_trade_share_allowed(
  p_type text,
  p_trade_id uuid,
  p_sender_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if p_trade_id is not null and coalesce(p_type, '') <> 'trade' then
    raise exception 'trade_id only allowed on trade messages'
      using errcode = '42501';
  end if;

  if coalesce(p_type, '') <> 'trade' then
    return;
  end if;

  if p_trade_id is null then
    raise exception 'trade messages require trade_id'
      using errcode = '23514';
  end if;

  if p_sender_id is null or p_sender_id is distinct from auth.uid() then
    raise exception 'trade share requires authenticated sender'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.trades t
    where t.id = p_trade_id
      and t.user_id = auth.uid()
  ) then
    raise exception 'you can only share trades you own'
      using errcode = '42501';
  end if;
end;
$$;

comment on function public.messages_assert_trade_share_allowed(text, uuid, uuid) is
  'Raises when a message row violates trade-share ownership rules (INSERT).';

-- =============================================================================
-- 2. INSERT guard
-- =============================================================================

create or replace function public.messages_before_insert_trade_share_guard()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform public.messages_assert_trade_share_allowed(
    new.type,
    new.trade_id,
    new.sender_id
  );
  return new;
end;
$$;

drop trigger if exists messages_before_insert_trade_share_guard on public.messages;

create trigger messages_before_insert_trade_share_guard
  before insert on public.messages
  for each row
  execute function public.messages_before_insert_trade_share_guard();

-- =============================================================================
-- 3. UPDATE guard — immutable type / trade_id (extend existing trigger function)
-- =============================================================================

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

-- =============================================================================
-- ROLLBACK (manual)
-- =============================================================================
-- drop trigger if exists messages_before_insert_trade_share_guard on public.messages;
-- drop function if exists public.messages_before_insert_trade_share_guard();
-- drop function if exists public.messages_assert_trade_share_allowed(text, uuid, uuid);
-- Re-apply messages_before_update_guard from 20260609150000_messaging_secure_rls.sql
