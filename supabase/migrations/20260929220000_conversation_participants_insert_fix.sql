-- Fix: authenticated users could self-insert into any conversation via
-- `user_id = auth.uid()` alone on conversation_participants INSERT.
--
-- Allowed:
--   • Bootstrap inserts while the conversation has zero participants (DM/group create).
--   • Existing participants adding members (group add, DM create second row in batch).

drop policy if exists "conversation_participants_insert_member" on public.conversation_participants;

create policy "conversation_participants_insert_member"
  on public.conversation_participants
  for insert
  to authenticated
  with check (
    not exists (
      select 1
      from public.conversation_participants cp
      where cp.conversation_id = conversation_participants.conversation_id
    )
    or public.is_conversation_participant(conversation_id, auth.uid())
  );

comment on policy "conversation_participants_insert_member" on public.conversation_participants is
  'Bootstrap empty conversations or add members when caller is already a participant — not self-join by conversation_id alone.';
