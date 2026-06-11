-- Phase 8: Secure RLS on public.notifications only.
-- Prerequisite: none (no application changes required).
--
-- Target:
--   SELECT  — user_id = auth.uid()
--   UPDATE  — user_id = auth.uid() (mark read / dismiss via read flag)
--   DELETE  — user_id = auth.uid()
--   INSERT  — typed, sender-scoped policies tied to real engagement actions
--
-- Preserves:
--   follow      — /api/notifications/follow (service role) + optional client insert
--   like        — feed + TradeSocialLayer client inserts (after like row exists)
--   comment     — feed + TradeSocialLayer client inserts (after comment row exists)
--   room_join   — /api/notifications/room-join (service role)
--   message     — owner read/update; insert policy for shared-conversation pairs
--
-- Pre-flight (run in SQL editor before applying):
--   select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
--   from pg_policies
--   where schemaname = 'public' and tablename = 'notifications'
--   order by policyname;

alter table public.notifications enable row level security;

-- =============================================================================
-- Drop legacy / pre-Phase-8 policies
-- =============================================================================
drop policy if exists "notifications_select_own" on public.notifications;
drop policy if exists "notifications_update_own" on public.notifications;
drop policy if exists "notifications_delete_own" on public.notifications;
drop policy if exists "notifications_insert_like" on public.notifications;
drop policy if exists "notifications_insert_comment" on public.notifications;
drop policy if exists "notifications_insert_message" on public.notifications;
drop policy if exists notifications_insert_follow on public.notifications;

drop policy if exists "Allow all notifications" on public.notifications;
drop policy if exists "Allow read notifications" on public.notifications;
drop policy if exists "Allow anyone to read notifications" on public.notifications;
drop policy if exists "TEMP allow all notifications" on public.notifications;
drop policy if exists "notifications_select_all" on public.notifications;
drop policy if exists "Users can read own notifications" on public.notifications;
drop policy if exists "Users can update own notifications" on public.notifications;
drop policy if exists "Users can delete own notifications" on public.notifications;
drop policy if exists "Users can insert notifications" on public.notifications;

-- =============================================================================
-- Owner read / write
-- =============================================================================
create policy "notifications_select_own"
  on public.notifications
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "notifications_update_own"
  on public.notifications
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "notifications_delete_own"
  on public.notifications
  for delete
  to authenticated
  using (user_id = auth.uid());

-- =============================================================================
-- Typed INSERT — only after a real engagement action exists
-- =============================================================================

-- Follow: sender followed recipient (followers row must exist).
create policy "notifications_insert_follow"
  on public.notifications
  for insert
  to authenticated
  with check (
    type = 'follow'
    and sender_id = auth.uid()
    and user_id is not null
    and user_id <> auth.uid()
    and exists (
      select 1
      from public.followers f
      where f.follower_id = auth.uid()
        and f.following_id = notifications.user_id
    )
  );

-- Like: sender liked a post or trade (matching like row must exist).
create policy "notifications_insert_like"
  on public.notifications
  for insert
  to authenticated
  with check (
    type = 'like'
    and sender_id = auth.uid()
    and user_id is not null
    and user_id <> auth.uid()
    and (
      (
        post_id is not null
        and exists (
          select 1
          from public.likes l
          where l.post_id = notifications.post_id
            and l.user_id = auth.uid()
        )
      )
      or (
        trade_id is not null
        and exists (
          select 1
          from public.trade_likes tl
          where tl.trade_id = notifications.trade_id
            and tl.user_id = auth.uid()
        )
      )
    )
  );

-- Comment: sender commented on a post or trade (matching comment row must exist).
create policy "notifications_insert_comment"
  on public.notifications
  for insert
  to authenticated
  with check (
    type = 'comment'
    and sender_id = auth.uid()
    and user_id is not null
    and user_id <> auth.uid()
    and (
      (
        post_id is not null
        and exists (
          select 1
          from public.comments c
          where c.post_id = notifications.post_id
            and c.user_id = auth.uid()
        )
      )
      or (
        trade_id is not null
        and exists (
          select 1
          from public.trade_comments tc
          where tc.trade_id = notifications.trade_id
            and tc.user_id = auth.uid()
        )
      )
    )
  );

-- Message: sender shares a conversation with recipient (no client insert today;
-- policy future-proofs DM notification inserts without opening arbitrary spam).
create policy "notifications_insert_message"
  on public.notifications
  for insert
  to authenticated
  with check (
    type = 'message'
    and sender_id = auth.uid()
    and user_id is not null
    and user_id <> auth.uid()
    and exists (
      select 1
      from public.conversation_participants cp_sender
      join public.conversation_participants cp_recipient
        on cp_recipient.conversation_id = cp_sender.conversation_id
      where cp_sender.user_id = auth.uid()
        and cp_recipient.user_id = notifications.user_id
    )
  );

-- room_join inserts use /api/notifications/room-join (service role bypasses RLS).

-- =============================================================================
-- Grants
-- =============================================================================
revoke all on table public.notifications from anon;
grant select, insert, update, delete on table public.notifications to authenticated;

-- =============================================================================
-- ROLLBACK (manual — INSECURE, emergency only)
-- =============================================================================
-- scripts/rollback-20260609210000-notifications-rls.sql
