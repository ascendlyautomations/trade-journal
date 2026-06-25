-- Deduplicate notifications across all engagement types and enforce uniqueness.

alter table public.notifications
  add column if not exists comment_id uuid,
  add column if not exists room_message_id uuid,
  add column if not exists room_id uuid;

-- Backfill room_message_id from JSON content.
update public.notifications n
set room_message_id = (n.content::jsonb ->> 'message_id')::uuid
where n.type = 'room_message'
  and n.room_message_id is null
  and n.content is not null
  and n.content ~ '^\s*\{'
  and (n.content::jsonb ->> 'message_id') ~* '^[0-9a-f-]{36}$';

-- Backfill room_id for room_join notifications via room slug in content.
update public.notifications n
set room_id = r.id
from public.rooms r
where n.type = 'room_join'
  and n.room_id is null
  and n.content is not null
  and n.content ~ '^\s*\{'
  and (n.content::jsonb ->> 'room_slug') = r.slug;

-- Remove duplicate follow notifications (keep earliest).
with ranked as (
  select
    id,
    row_number() over (
      partition by user_id, sender_id
      order by created_at asc, id asc
    ) as rn
  from public.notifications
  where type = 'follow'
)
delete from public.notifications n
using ranked r
where n.id = r.id
  and r.rn > 1;

-- Remove duplicate follow_request notifications (keep earliest).
with ranked as (
  select
    id,
    row_number() over (
      partition by user_id, sender_id
      order by created_at asc, id asc
    ) as rn
  from public.notifications
  where type = 'follow_request'
)
delete from public.notifications n
using ranked r
where n.id = r.id
  and r.rn > 1;

-- Remove duplicate comment notifications when comment_id is set.
with ranked as (
  select
    id,
    row_number() over (
      partition by user_id, comment_id
      order by created_at asc, id asc
    ) as rn
  from public.notifications
  where type = 'comment'
    and comment_id is not null
)
delete from public.notifications n
using ranked r
where n.id = r.id
  and r.rn > 1;

-- Remove duplicate room_message notifications when room_message_id is set.
with ranked as (
  select
    id,
    row_number() over (
      partition by user_id, room_message_id
      order by created_at asc, id asc
    ) as rn
  from public.notifications
  where type = 'room_message'
    and room_message_id is not null
)
delete from public.notifications n
using ranked r
where n.id = r.id
  and r.rn > 1;

-- Remove duplicate room_join notifications per owner + joiner + room.
with ranked as (
  select
    id,
    row_number() over (
      partition by user_id, sender_id, room_id
      order by created_at asc, id asc
    ) as rn
  from public.notifications
  where type = 'room_join'
    and room_id is not null
)
delete from public.notifications n
using ranked r
where n.id = r.id
  and r.rn > 1;

create unique index if not exists notifications_follow_unique_idx
  on public.notifications (user_id, sender_id)
  where type = 'follow';

create unique index if not exists notifications_follow_request_unique_idx
  on public.notifications (user_id, sender_id)
  where type = 'follow_request';

create unique index if not exists notifications_comment_unique_idx
  on public.notifications (user_id, comment_id)
  where type = 'comment'
    and comment_id is not null;

create unique index if not exists notifications_room_message_unique_idx
  on public.notifications (user_id, room_message_id)
  where type = 'room_message'
    and room_message_id is not null;

create unique index if not exists notifications_room_join_unique_idx
  on public.notifications (user_id, sender_id, room_id)
  where type = 'room_join'
    and room_id is not null;

-- Comment authors can delete their comment notifications when removing a comment.
create policy notifications_delete_comment_sender
  on public.notifications
  for delete
  to authenticated
  using (
    type = 'comment'
    and sender_id = auth.uid()
  );

-- Server-side cleanup when comments are deleted.
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
