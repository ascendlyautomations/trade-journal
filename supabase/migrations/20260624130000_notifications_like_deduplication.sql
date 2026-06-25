-- Deduplicate like notifications and enforce one active notification per liker + target.

-- Remove duplicate like notifications (keep the earliest row per actor + target).
with ranked as (
  select
    id,
    row_number() over (
      partition by
        user_id,
        sender_id,
        case
          when profile_post_id is not null then 'pp:' || profile_post_id::text
          when post_id is not null then 'p:' || post_id::text
          when trade_id is not null then 't:' || trade_id::text
          else 'unknown:' || id::text
        end
      order by created_at asc, id asc
    ) as rn
  from public.notifications
  where type = 'like'
)
delete from public.notifications n
using ranked r
where n.id = r.id
  and r.rn > 1;

-- One like notification per recipient + sender + trade (direct trade likes only).
create unique index if not exists notifications_like_trade_unique_idx
  on public.notifications (user_id, sender_id, trade_id)
  where type = 'like'
    and trade_id is not null
    and post_id is null
    and profile_post_id is null;

-- One like notification per recipient + sender + feed post.
create unique index if not exists notifications_like_post_unique_idx
  on public.notifications (user_id, sender_id, post_id)
  where type = 'like'
    and post_id is not null
    and profile_post_id is null;

-- One like notification per recipient + sender + profile post.
create unique index if not exists notifications_like_profile_post_unique_idx
  on public.notifications (user_id, sender_id, profile_post_id)
  where type = 'like'
    and profile_post_id is not null;

-- Server-side cleanup when a like row is removed (covers all unlike paths).
create or replace function public.sync_delete_like_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_table_name = 'trade_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and trade_id = old.trade_id
      and post_id is null
      and profile_post_id is null;
  elsif tg_table_name = 'likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and post_id = old.post_id
      and profile_post_id is null;
  elsif tg_table_name = 'profile_post_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and profile_post_id = old.profile_post_id;
  end if;

  return old;
end;
$$;

drop trigger if exists trade_likes_sync_delete_like_notification on public.trade_likes;
create trigger trade_likes_sync_delete_like_notification
  after delete on public.trade_likes
  for each row
  execute function public.sync_delete_like_notification();

drop trigger if exists likes_sync_delete_like_notification on public.likes;
create trigger likes_sync_delete_like_notification
  after delete on public.likes
  for each row
  execute function public.sync_delete_like_notification();

drop trigger if exists profile_post_likes_sync_delete_like_notification on public.profile_post_likes;
create trigger profile_post_likes_sync_delete_like_notification
  after delete on public.profile_post_likes
  for each row
  execute function public.sync_delete_like_notification();
