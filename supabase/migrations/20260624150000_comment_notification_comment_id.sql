-- Enforce comment_id on comment notifications and repair existing rows.

-- Backfill feed post comment notifications.
update public.notifications n
set comment_id = c.id
from public.comments c
where n.type = 'comment'
  and n.comment_id is null
  and n.post_id is not null
  and n.post_id = c.post_id
  and n.sender_id = c.user_id
  and n.content = left(trim(c.content), 200);

-- Backfill trade comment notifications.
update public.notifications n
set comment_id = c.id
from public.trade_comments c
where n.type = 'comment'
  and n.comment_id is null
  and n.trade_id is not null
  and n.profile_post_id is null
  and n.trade_id = c.trade_id
  and n.sender_id = c.user_id
  and n.content = left(trim(c.content), 200);

-- Backfill profile post comment notifications.
update public.notifications n
set comment_id = c.id
from public.profile_post_comments c
where n.type = 'comment'
  and n.comment_id is null
  and n.profile_post_id is not null
  and n.profile_post_id = c.profile_post_id
  and n.sender_id = c.user_id
  and n.content = left(trim(c.content), 200);

-- Remove stale comment notifications that no longer have a source comment.
delete from public.notifications n
where n.type = 'comment'
  and n.comment_id is null;

-- Every new comment notification must reference its source comment.
alter table public.notifications
  drop constraint if exists notifications_comment_requires_comment_id;

alter table public.notifications
  add constraint notifications_comment_requires_comment_id
  check (type is distinct from 'comment' or comment_id is not null);

-- Ensure comment authors can delete their notifications (idempotent).
drop policy if exists notifications_delete_comment_sender on public.notifications;
create policy notifications_delete_comment_sender
  on public.notifications
  for delete
  to authenticated
  using (
    type = 'comment'
    and sender_id = auth.uid()
  );

-- Ensure delete trigger exists on all comment tables (idempotent).
create or replace function public.sync_delete_comment_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.notifications
  where type = 'comment'
    and comment_id = old.id;
  return old;
end;
$$;

drop trigger if exists comments_sync_delete_comment_notification on public.comments;
create trigger comments_sync_delete_comment_notification
  after delete on public.comments
  for each row
  execute function public.sync_delete_comment_notification();

drop trigger if exists trade_comments_sync_delete_comment_notification on public.trade_comments;
create trigger trade_comments_sync_delete_comment_notification
  after delete on public.trade_comments
  for each row
  execute function public.sync_delete_comment_notification();

drop trigger if exists profile_post_comments_sync_delete_comment_notification on public.profile_post_comments;
create trigger profile_post_comments_sync_delete_comment_notification
  after delete on public.profile_post_comments
  for each row
  execute function public.sync_delete_comment_notification();
