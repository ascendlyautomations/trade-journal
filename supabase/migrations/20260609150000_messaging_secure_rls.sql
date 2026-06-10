-- Phase 2: Messaging security — RLS on direct messaging infrastructure.
-- Prerequisite: Phase 1 application changes deployed (participant gates, Navbar off
-- direct_messages, unread helper on messages + conversation_participants + seen_by).
--
-- Tables secured (no schema changes):
--   conversation_participants, conversations, messages (DM + public lobby split),
--   message_deletions, message_likes, message_comments, direct_messages (lockdown)
--
-- Does NOT modify: room_messages, room_members, rooms, trades, or other tables.
--
-- Pre-flight (run in SQL editor before applying):
--   select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
--   from pg_policies
--   where schemaname = 'public'
--     and tablename in (
--       'conversation_participants', 'conversations', 'messages',
--       'message_deletions', 'message_likes', 'message_comments', 'direct_messages'
--     )
--   order by tablename, policyname;

-- =============================================================================
-- 1. Helpers
-- =============================================================================

create or replace function public.is_conversation_participant(
  p_conversation_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = p_conversation_id
      and cp.user_id = p_user_id
  );
$$;

comment on function public.is_conversation_participant(uuid, uuid) is
  'True when p_user_id has a row in conversation_participants for p_conversation_id.';

-- DM / group messages: participants may only mutate seen_by on others'' rows unless sender.
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
       or old.type is distinct from new.type
       or old.trade_id is distinct from new.trade_id
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
     or old.type is distinct from new.type
     or old.trade_id is distinct from new.trade_id
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

drop trigger if exists messages_before_update_guard on public.messages;

create trigger messages_before_update_guard
  before update on public.messages
  for each row
  execute function public.messages_before_update_guard();

-- =============================================================================
-- 2. Remove dangerous / legacy policies (safe if absent)
-- =============================================================================

-- conversation_participants
drop policy if exists "Users can delete participants in their conversations" on public.conversation_participants;
drop policy if exists "TEMP allow all conversation_participants" on public.conversation_participants;
drop policy if exists "Allow anyone to read conversation_participants" on public.conversation_participants;
drop policy if exists "Allow all conversation_participants" on public.conversation_participants;
drop policy if exists "conversation_participants_select_all" on public.conversation_participants;
drop policy if exists "conversation_participants_insert_all" on public.conversation_participants;
drop policy if exists "conversation_participants_delete_all" on public.conversation_participants;
drop policy if exists "conversation_participants_select_own" on public.conversation_participants;
drop policy if exists "conversation_participants_select_shared" on public.conversation_participants;
drop policy if exists "conversation_participants_insert_member" on public.conversation_participants;
drop policy if exists "conversation_participants_delete_self" on public.conversation_participants;

-- conversations
drop policy if exists "Users can delete their conversations" on public.conversations;
drop policy if exists "TEMP allow all conversations" on public.conversations;
drop policy if exists "Allow anyone to read conversations" on public.conversations;
drop policy if exists "Allow all conversations" on public.conversations;
drop policy if exists "conversations_select_all" on public.conversations;
drop policy if exists "conversations_insert_authenticated" on public.conversations;
drop policy if exists "conversations_update_participant" on public.conversations;
drop policy if exists "conversations_delete_creator" on public.conversations;

-- messages
drop policy if exists "TEMP allow all messages" on public.messages;
drop policy if exists "TEMP allow inserts" on public.messages;
drop policy if exists "Users can delete messages in their conversations" on public.messages;
drop policy if exists "users can update messages in their conversations" on public.messages;
drop policy if exists "Allow anyone to read messages" on public.messages;
drop policy if exists "Allow all messages" on public.messages;
drop policy if exists "messages_select_all" on public.messages;
drop policy if exists "messages_select_conversation_participant" on public.messages;
drop policy if exists "messages_select_lobby_authenticated" on public.messages;
drop policy if exists "messages_select_own" on public.messages;
drop policy if exists "messages_insert_conversation_participant" on public.messages;
drop policy if exists "messages_insert_lobby_authenticated" on public.messages;
drop policy if exists "messages_update_sender" on public.messages;
drop policy if exists "messages_update_seen_by_participant" on public.messages;
drop policy if exists "messages_update_lobby_author" on public.messages;
drop policy if exists "messages_delete_sender" on public.messages;
drop policy if exists "messages_delete_lobby_author" on public.messages;

-- message_deletions
drop policy if exists "TEMP allow all message_deletions" on public.message_deletions;
drop policy if exists "Allow anyone to read message_deletions" on public.message_deletions;
drop policy if exists "message_deletions_select_own" on public.message_deletions;
drop policy if exists "message_deletions_insert_own" on public.message_deletions;

-- message_likes
drop policy if exists "TEMP allow all message_likes" on public.message_likes;
drop policy if exists "Allow anyone to read message_likes" on public.message_likes;
drop policy if exists "message_likes_select_authenticated" on public.message_likes;
drop policy if exists "message_likes_insert_own" on public.message_likes;
drop policy if exists "message_likes_delete_own" on public.message_likes;

-- message_comments
drop policy if exists "TEMP allow all message_comments" on public.message_comments;
drop policy if exists "Allow anyone to read message_comments" on public.message_comments;
drop policy if exists "message_comments_select_authenticated" on public.message_comments;
drop policy if exists "message_comments_insert_own" on public.message_comments;
drop policy if exists "message_comments_delete_own" on public.message_comments;

-- direct_messages (legacy)
drop policy if exists "Allow inserts" on public.direct_messages;
drop policy if exists "TEMP allow all direct_messages" on public.direct_messages;
drop policy if exists "Allow anyone to read direct_messages" on public.direct_messages;
drop policy if exists "Allow all direct_messages" on public.direct_messages;
drop policy if exists "direct_messages_select_recipient" on public.direct_messages;
drop policy if exists "direct_messages_insert_sender" on public.direct_messages;
drop policy if exists "direct_messages_update_recipient" on public.direct_messages;

-- =============================================================================
-- 3. conversation_participants
-- =============================================================================

alter table public.conversation_participants enable row level security;

-- SELECT: own membership rows + co-participants in shared conversations
create policy "conversation_participants_select_own"
  on public.conversation_participants
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or public.is_conversation_participant(conversation_id, auth.uid())
  );

-- INSERT: self-join, existing participant adds member, or bootstrap empty conversation
-- (bootstrap supports single-statement multi-row DM/group creation in app)
create policy "conversation_participants_insert_member"
  on public.conversation_participants
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    or public.is_conversation_participant(conversation_id, auth.uid())
    or not exists (
      select 1
      from public.conversation_participants cp
      where cp.conversation_id = conversation_participants.conversation_id
    )
  );

-- DELETE: leave conversation (self only)
create policy "conversation_participants_delete_self"
  on public.conversation_participants
  for delete
  to authenticated
  using (
    user_id = auth.uid()
  );

grant select, insert, delete on table public.conversation_participants to authenticated;

-- =============================================================================
-- 4. conversations
-- =============================================================================

alter table public.conversations enable row level security;

-- SELECT: participants only
create policy "conversations_select_participant"
  on public.conversations
  for select
  to authenticated
  using (
    public.is_conversation_participant(id, auth.uid())
  );

-- INSERT: any authenticated user may create a conversation shell
create policy "conversations_insert_authenticated"
  on public.conversations
  for insert
  to authenticated
  with check (
    auth.uid() is not null
  );

-- UPDATE: participants (metadata: name, avatar, last_message, is_pinned, etc.)
create policy "conversations_update_participant"
  on public.conversations
  for update
  to authenticated
  using (
    public.is_conversation_participant(id, auth.uid())
  )
  with check (
    public.is_conversation_participant(id, auth.uid())
  );

-- DELETE: not used by application today — no policy (deny by default)

grant select, insert, update on table public.conversations to authenticated;

-- =============================================================================
-- 5. messages — conversation (DM / group) + public lobby (channel) split
-- =============================================================================

alter table public.messages enable row level security;

-- SELECT: conversation participants (DM / group)
create policy "messages_select_conversation_participant"
  on public.messages
  for select
  to authenticated
  using (
    conversation_id is not null
    and public.is_conversation_participant(conversation_id, auth.uid())
  );

-- SELECT: public lobby (channel-based global chat)
create policy "messages_select_lobby_authenticated"
  on public.messages
  for select
  to authenticated
  using (
    channel is not null
  );

-- SELECT: author read own rows (free-plan limits in lib/freePlanLimits.ts)
create policy "messages_select_own"
  on public.messages
  for select
  to authenticated
  using (
    sender_id = auth.uid()
    or user_id = auth.uid()
  );

-- INSERT: conversation messages — participants; sender=self or system (sender_id null)
create policy "messages_insert_conversation_participant"
  on public.messages
  for insert
  to authenticated
  with check (
    conversation_id is not null
    and channel is null
    and public.is_conversation_participant(conversation_id, auth.uid())
    and (
      sender_id = auth.uid()
      or sender_id is null
    )
  );

-- INSERT: public lobby — authenticated, post as self
create policy "messages_insert_lobby_authenticated"
  on public.messages
  for insert
  to authenticated
  with check (
    channel is not null
    and conversation_id is null
    and user_id = auth.uid()
  );

-- UPDATE: conversation message sender (soft delete, own fields)
create policy "messages_update_sender"
  on public.messages
  for update
  to authenticated
  using (
    conversation_id is not null
    and sender_id = auth.uid()
    and public.is_conversation_participant(conversation_id, auth.uid())
  )
  with check (
    conversation_id is not null
    and sender_id = auth.uid()
    and public.is_conversation_participant(conversation_id, auth.uid())
  );

-- UPDATE: seen_by — participants on others'' / system conversation messages (trigger guards columns)
create policy "messages_update_seen_by_participant"
  on public.messages
  for update
  to authenticated
  using (
    conversation_id is not null
    and public.is_conversation_participant(conversation_id, auth.uid())
    and (sender_id is null or sender_id <> auth.uid())
  )
  with check (
    conversation_id is not null
    and public.is_conversation_participant(conversation_id, auth.uid())
    and (sender_id is null or sender_id <> auth.uid())
  );

-- UPDATE: lobby author own messages
create policy "messages_update_lobby_author"
  on public.messages
  for update
  to authenticated
  using (
    channel is not null
    and user_id = auth.uid()
  )
  with check (
    channel is not null
    and user_id = auth.uid()
  );

-- DELETE: conversation sender hard-delete (if used)
create policy "messages_delete_sender"
  on public.messages
  for delete
  to authenticated
  using (
    conversation_id is not null
    and sender_id = auth.uid()
    and public.is_conversation_participant(conversation_id, auth.uid())
  );

-- DELETE: lobby author own messages
create policy "messages_delete_lobby_author"
  on public.messages
  for delete
  to authenticated
  using (
    channel is not null
    and user_id = auth.uid()
  );

grant select, insert, update, delete on table public.messages to authenticated;

-- =============================================================================
-- 6. message_deletions (per-user hide)
-- =============================================================================

alter table public.message_deletions enable row level security;

create policy "message_deletions_select_own"
  on public.message_deletions
  for select
  to authenticated
  using (
    user_id = auth.uid()
  );

create policy "message_deletions_insert_own"
  on public.message_deletions
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
  );

grant select, insert on table public.message_deletions to authenticated;

-- =============================================================================
-- 7. message_likes (public lobby reactions)
-- =============================================================================

alter table public.message_likes enable row level security;

create policy "message_likes_select_authenticated"
  on public.message_likes
  for select
  to authenticated
  using (
    auth.uid() is not null
  );

create policy "message_likes_insert_own"
  on public.message_likes
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
  );

create policy "message_likes_delete_own"
  on public.message_likes
  for delete
  to authenticated
  using (
    user_id = auth.uid()
  );

grant select, insert, delete on table public.message_likes to authenticated;

-- =============================================================================
-- 8. message_comments (legacy public chat; no active app paths — secured for parity)
-- =============================================================================

alter table public.message_comments enable row level security;

create policy "message_comments_select_authenticated"
  on public.message_comments
  for select
  to authenticated
  using (
    auth.uid() is not null
  );

create policy "message_comments_insert_own"
  on public.message_comments
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
  );

create policy "message_comments_delete_own"
  on public.message_comments
  for delete
  to authenticated
  using (
    user_id = auth.uid()
  );

grant select, insert, delete on table public.message_comments to authenticated;

-- =============================================================================
-- 9. direct_messages — legacy lockdown (app no longer reads this table)
-- =============================================================================

alter table public.direct_messages enable row level security;

-- Revoke API access; RLS enabled with zero permissive policies = deny all.
revoke all on table public.direct_messages from anon;
revoke all on table public.direct_messages from authenticated;

-- =============================================================================
-- ROLLBACK (manual — INSECURE, emergency only)
-- =============================================================================
-- See policy drop list in section 2; disable RLS per table; restore permissive policies.
-- drop trigger if exists messages_before_update_guard on public.messages;
-- drop function if exists public.messages_before_update_guard();
-- drop function if exists public.is_conversation_participant(uuid, uuid);
