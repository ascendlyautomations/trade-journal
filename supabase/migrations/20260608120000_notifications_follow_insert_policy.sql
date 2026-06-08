-- Allow authenticated clients to insert follow notifications directly (optional).
-- Primary path uses /api/notifications/follow with service role; this policy supports that pattern too.

drop policy if exists notifications_insert_follow on public.notifications;

create policy notifications_insert_follow
  on public.notifications
  for insert
  to authenticated
  with check (
    type = 'follow'
    and sender_id = auth.uid()
    and user_id is not null
    and user_id <> auth.uid()
  );
