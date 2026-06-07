-- Phase 4: Trade Room security — RLS on public.room_presence only.
-- Depends on Phase 1: public.is_active_room_member(uuid, uuid)
-- Depends on Phase 3: room_members RLS (self-select policy for invoker membership checks)
-- Does not modify rooms, room_messages, room_members, or room_sections.
--
-- Prerequisites (production):
--   - public.room_presence table with unique (room_id, user_id) for app upsert
--   - Application heartbeats via upsert { room_id, user_id, last_seen }
--   - Phase 3B room_members RLS applied (is_active_room_member reads caller row)
--
-- Deploy atomically: all policies must exist before ENABLE ROW LEVEL SECURITY.

-- =============================================================================
-- UPDATE guard: only last_seen may change (heartbeat upsert path)
-- =============================================================================

create or replace function public.room_presence_before_update_guard()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.room_id is distinct from new.room_id
     or old.user_id is distinct from new.user_id
  then
    raise exception 'room_id and user_id are immutable on room_presence';
  end if;

  return new;
end;
$$;

drop trigger if exists room_presence_before_update_guard on public.room_presence;

create trigger room_presence_before_update_guard
  before update on public.room_presence
  for each row
  execute function public.room_presence_before_update_guard();

-- =============================================================================
-- RLS policies
-- =============================================================================

alter table public.room_presence enable row level security;

-- SELECT: active room members only (online avatars + active trader count)
drop policy if exists "room_presence_select_member" on public.room_presence;
create policy "room_presence_select_member"
  on public.room_presence
  for select
  to authenticated
  using (
    public.is_active_room_member(room_id, auth.uid())
  );

-- INSERT: own presence only; must be active member (blocks spoofing + non-member)
drop policy if exists "room_presence_insert_self" on public.room_presence;
create policy "room_presence_insert_self"
  on public.room_presence
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
  );

-- UPDATE: own heartbeat only; active membership required (upsert conflict path)
drop policy if exists "room_presence_update_self" on public.room_presence;
create policy "room_presence_update_self"
  on public.room_presence
  for update
  to authenticated
  using (
    user_id = auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
  )
  with check (
    user_id = auth.uid()
    and public.is_active_room_member(room_id, auth.uid())
  );

-- DELETE: own row only (future leave/unmount cleanup; not used in app today)
drop policy if exists "room_presence_delete_self" on public.room_presence;
create policy "room_presence_delete_self"
  on public.room_presence
  for delete
  to authenticated
  using (
    user_id = auth.uid()
  );

-- =============================================================================
-- ROLLBACK (run manually to revert this migration)
-- =============================================================================
-- drop policy if exists "room_presence_select_member" on public.room_presence;
-- drop policy if exists "room_presence_insert_self" on public.room_presence;
-- drop policy if exists "room_presence_update_self" on public.room_presence;
-- drop policy if exists "room_presence_delete_self" on public.room_presence;
--
-- drop trigger if exists room_presence_before_update_guard on public.room_presence;
-- drop function if exists public.room_presence_before_update_guard();
--
-- alter table public.room_presence disable row level security;

-- =============================================================================
-- DEPLOYMENT CHECKLIST
-- =============================================================================
-- [ ] Phase 1 applied (rooms RLS + is_active_room_member)
-- [ ] Phase 2 applied (room_messages RLS)
-- [ ] Phase 3B applied (room_members RLS + self-select policy)
-- [ ] public.room_presence exists with unique (room_id, user_id)
-- [ ] Apply this migration in a single transaction
-- [ ] Verify joined member: upsert heartbeat succeeds
-- [ ] Verify joined member: SELECT returns rows for room within 30s window
-- [ ] Verify online avatars and "N active traders" still render
-- [ ] Verify non-member: INSERT/UPDATE/SELECT denied
-- [ ] Verify soft-left member (left_at set): INSERT/UPDATE/SELECT denied
-- [ ] Verify spoofed user_id in upsert payload: denied
-- [ ] Verify anon: all operations denied
-- [ ] Verify cross-room SELECT denied for non-member rooms
-- [ ] Verify self DELETE succeeds (optional manual test)

-- =============================================================================
-- EDGE CASES
-- =============================================================================
-- 1. Upsert requires both INSERT and UPDATE policies. PostgREST upsert uses
--    INSERT ... ON CONFLICT DO UPDATE; first heartbeat INSERTs, subsequent
--    heartbeats UPDATE last_seen only (trigger blocks room_id/user_id change).
--
-- 2. is_active_room_member is security invoker. SELECT/INSERT/UPDATE policies
--    pass auth.uid() as member — caller reads own room_members row via Phase 3
--    room_members_select_self. Do not enable this migration before Phase 3B.
--
-- 3. SELECT returns all presence rows in a room visible to active members,
--    including users who soft-left within the last_seen window (app does not
--    DELETE presence on leave). UI filters last_seen > 30s ago; ghost presence
--    expires within ~30s without a subject-membership filter on SELECT.
--
-- 4. Subject-membership filter (hide left users immediately) would require a
--    security definer helper — not included; invoker cannot read others'
--    room_members rows for non-owners.
--
-- 5. Soft-left member mid-session: next heartbeat UPDATE fails (membership
--    check false); SELECT also fails — user stops appearing online to others
--    and loses presence read access immediately after leave.
--
-- 6. profiles embed on SELECT (username, avatar_url) depends on profiles RLS
--    separately; room_presence policies do not govern profile visibility.
--
-- 7. last_seen column may be timestamp without time zone in production; app
--    sends ISO strings. RLS does not validate last_seen semantics.
--
-- 8. Service role bypasses RLS. Application uses authenticated key only.
