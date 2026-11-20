-- Trade Room live broadcast: Supabase Realtime publication + scoped SELECT RLS for native clients.
-- Writes remain BFF/service-role only.

create or replace function public.broadcast_session_room_id(p_session_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select b.room_id
  from public.room_live_broadcasts b
  where b.id = p_session_id
  limit 1;
$$;

comment on function public.broadcast_session_room_id(uuid) is
  'Resolves room_id for a broadcast session — used by broadcast interactive RLS.';

revoke all on function public.broadcast_session_room_id(uuid) from public;
grant execute on function public.broadcast_session_room_id(uuid) to authenticated;

-- Active Trade Room members may read discoverable session metadata for their room.
drop policy if exists "room_live_broadcasts_select_active_member" on public.room_live_broadcasts;
create policy "room_live_broadcasts_select_active_member"
  on public.room_live_broadcasts
  for select
  to authenticated
  using (
    public.is_active_room_member(room_id, (select auth.uid()))
    and not public.is_room_banned(room_id, (select auth.uid()))
  );

drop policy if exists "room_live_broadcast_hands_select_member" on public.room_live_broadcast_hands;
create policy "room_live_broadcast_hands_select_member"
  on public.room_live_broadcast_hands
  for select
  to authenticated
  using (
    public.is_active_room_member(
      public.broadcast_session_room_id(broadcast_session_id),
      (select auth.uid())
    )
    and not public.is_room_banned(
      public.broadcast_session_room_id(broadcast_session_id),
      (select auth.uid())
    )
  );

drop policy if exists "room_live_broadcast_speaker_grants_select_member" on public.room_live_broadcast_speaker_grants;
create policy "room_live_broadcast_speaker_grants_select_member"
  on public.room_live_broadcast_speaker_grants
  for select
  to authenticated
  using (
    public.is_active_room_member(
      public.broadcast_session_room_id(broadcast_session_id),
      (select auth.uid())
    )
    and not public.is_room_banned(
      public.broadcast_session_room_id(broadcast_session_id),
      (select auth.uid())
    )
  );

-- Viewers see only their own session block; hosts/moderators see all blocks for the session.
drop policy if exists "room_live_broadcast_session_blocks_select_scoped" on public.room_live_broadcast_session_blocks;
create policy "room_live_broadcast_session_blocks_select_scoped"
  on public.room_live_broadcast_session_blocks
  for select
  to authenticated
  using (
  (
    user_id = (select auth.uid())
    and public.is_active_room_member(
      public.broadcast_session_room_id(broadcast_session_id),
      (select auth.uid())
    )
  )
  or public.can_moderate_trade_room(
    public.broadcast_session_room_id(broadcast_session_id),
    (select auth.uid())
  )
  );

-- Invitees see their row; broadcaster + moderators see pending invites they manage.
drop policy if exists "room_live_broadcast_invitations_select_scoped" on public.room_live_broadcast_invitations;
create policy "room_live_broadcast_invitations_select_scoped"
  on public.room_live_broadcast_invitations
  for select
  to authenticated
  using (
    (
      user_id = (select auth.uid())
      and public.is_active_room_member(
        public.broadcast_session_room_id(broadcast_session_id),
        (select auth.uid())
      )
    )
    or exists (
      select 1
      from public.room_live_broadcasts b
      where b.id = broadcast_session_id
        and b.broadcaster_user_id = (select auth.uid())
        and b.ended_at is null
    )
    or public.can_moderate_trade_room(
      public.broadcast_session_room_id(broadcast_session_id),
      (select auth.uid())
    )
  );

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'room_live_broadcasts'
    ) then
      alter publication supabase_realtime add table public.room_live_broadcasts;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'room_live_broadcast_hands'
    ) then
      alter publication supabase_realtime add table public.room_live_broadcast_hands;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'room_live_broadcast_speaker_grants'
    ) then
      alter publication supabase_realtime add table public.room_live_broadcast_speaker_grants;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'room_live_broadcast_session_blocks'
    ) then
      alter publication supabase_realtime add table public.room_live_broadcast_session_blocks;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'room_live_broadcast_invitations'
    ) then
      alter publication supabase_realtime add table public.room_live_broadcast_invitations;
    end if;
  end if;
end $$;