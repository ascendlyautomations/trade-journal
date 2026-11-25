-- Private trade sharing in Trade Rooms (message-scoped read via RLS).
-- Prerequisite: 20260609220000_trades_select_shared_in_conversation.sql,
--               room message read helpers (is_active_room_member, can_read_trade_room_messages).
--
-- Does NOT set is_public; shared private trades stay off feed/profile/explore.

drop policy if exists "trades_select_shared_in_trade_room" on public.trades;

create policy "trades_select_shared_in_trade_room"
  on public.trades
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.room_messages rm
      where rm.trade_id = trades.id
        and lower(coalesce(rm.type, '')) = 'trade'
        and (
          public.is_active_room_member(rm.room_id, auth.uid())
          or public.can_read_trade_room_messages(rm.room_id)
        )
    )
  );

comment on policy "trades_select_shared_in_trade_room" on public.trades is
  'Authenticated users may read trades shared as type=trade room messages when they can read that room.';

-- =============================================================================
-- ROLLBACK (manual)
-- =============================================================================
-- drop policy if exists "trades_select_shared_in_trade_room" on public.trades;