-- Private trade sharing: conversation participants may read trades shared via DM/group messages.
-- Prerequisite: 20260609120000_trades_secure_rls.sql, 20260609150000_messaging_secure_rls.sql
--               (is_conversation_participant must exist).
--
-- Visibility model (permissive OR across policies):
--   trades_select_own                        — owner
--   trades_select_public                     — is_public = true
--   trades_select_shared_in_conversation     — trade referenced by type='trade' message in a
--                                              conversation the viewer participates in
--
-- Does NOT set is_public; shared private trades stay off feed/profile/explore.

drop policy if exists "trades_select_shared_in_conversation" on public.trades;

create policy "trades_select_shared_in_conversation"
  on public.trades
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.messages m
      where m.trade_id = trades.id
        and m.type = 'trade'
        and m.conversation_id is not null
        and public.is_conversation_participant(m.conversation_id, auth.uid())
    )
  );

comment on policy "trades_select_shared_in_conversation" on public.trades is
  'Authenticated users may read trades shared as type=trade messages in conversations they participate in.';

-- =============================================================================
-- ROLLBACK (manual — removes shared-in-conversation read access)
-- =============================================================================
-- drop policy if exists "trades_select_shared_in_conversation" on public.trades;
