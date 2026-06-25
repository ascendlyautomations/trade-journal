-- Allow likers to remove their like notifications when unliking content.

create policy notifications_delete_like_sender
  on public.notifications
  for delete
  to authenticated
  using (
    type = 'like'
    and sender_id = auth.uid()
  );
