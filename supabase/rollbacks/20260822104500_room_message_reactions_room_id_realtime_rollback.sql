-- Rollback: room_message_reactions room_id Realtime scope (Phase F2)
-- Apply manually if reverting 20260822104500_room_message_reactions_room_id_realtime.sql
--
-- PUBLICATION: Do NOT remove room_message_reactions from supabase_realtime here.
-- The table was already receiving Realtime subscription acks before this migration
-- (likely enabled via dashboard). Removing it would break unrelated environments.
-- If Phase F2 was the first publisher in your project, remove manually:
--   ALTER PUBLICATION supabase_realtime DROP TABLE public.room_message_reactions;

drop trigger if exists room_message_reactions_set_room_id on public.room_message_reactions;
drop function if exists public.room_message_reactions_set_room_id();

drop policy if exists "room_message_reactions_select_member" on public.room_message_reactions;
create policy "room_message_reactions_select_member"
  on public.room_message_reactions
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.room_messages rm
      where rm.id = message_id
        and public.is_active_room_member(rm.room_id, auth.uid())
    )
  );

drop policy if exists "room_message_reactions_insert_member" on public.room_message_reactions;
create policy "room_message_reactions_insert_member"
  on public.room_message_reactions
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.room_messages rm
      where rm.id = message_id
        and public.is_active_room_member(rm.room_id, auth.uid())
    )
  );

drop policy if exists "room_message_reactions_delete_own" on public.room_message_reactions;
create policy "room_message_reactions_delete_own"
  on public.room_message_reactions
  for delete
  to authenticated
  using (
    user_id = auth.uid()
    and exists (
      select 1
      from public.room_messages rm
      where rm.id = message_id
        and public.is_active_room_member(rm.room_id, auth.uid())
    )
  );

drop index if exists public.room_message_reactions_room_id_idx;
alter table public.room_message_reactions drop column if exists room_id;
