-- Comment likes: unified like table for all comment sources.

create table if not exists public.comment_likes (
  id uuid primary key default gen_random_uuid(),
  comment_source text not null check (
    comment_source in (
      'comments',
      'trade_comments',
      'profile_post_comments',
      'achievement_post_comments',
      'reel_comments'
    )
  ),
  comment_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (comment_source, comment_id, user_id)
);

create index if not exists comment_likes_lookup_idx
  on public.comment_likes (comment_source, comment_id);

create index if not exists comment_likes_user_id_idx
  on public.comment_likes (user_id);

alter table public.comment_likes enable row level security;

drop policy if exists comment_likes_insert_own on public.comment_likes;
create policy comment_likes_insert_own
  on public.comment_likes for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists comment_likes_delete_own on public.comment_likes;
create policy comment_likes_delete_own
  on public.comment_likes for delete to authenticated
  using (auth.uid() = user_id);

drop policy if exists comment_likes_select_authenticated on public.comment_likes;
create policy comment_likes_select_authenticated
  on public.comment_likes for select to authenticated using (true);

grant select, insert, delete on table public.comment_likes to authenticated;

-- Remove likes when a comment row is deleted (no FK across comment tables).
create or replace function public.sync_delete_comment_likes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.comment_likes
  where comment_source = tg_table_name
    and comment_id = old.id;
  return old;
end;
$$;

drop trigger if exists comments_sync_delete_comment_likes on public.comments;
create trigger comments_sync_delete_comment_likes
  after delete on public.comments
  for each row execute function public.sync_delete_comment_likes();

drop trigger if exists trade_comments_sync_delete_comment_likes on public.trade_comments;
create trigger trade_comments_sync_delete_comment_likes
  after delete on public.trade_comments
  for each row execute function public.sync_delete_comment_likes();

drop trigger if exists profile_post_comments_sync_delete_comment_likes on public.profile_post_comments;
create trigger profile_post_comments_sync_delete_comment_likes
  after delete on public.profile_post_comments
  for each row execute function public.sync_delete_comment_likes();

drop trigger if exists achievement_post_comments_sync_delete_comment_likes on public.achievement_post_comments;
create trigger achievement_post_comments_sync_delete_comment_likes
  after delete on public.achievement_post_comments
  for each row execute function public.sync_delete_comment_likes();

drop trigger if exists reel_comments_sync_delete_comment_likes on public.reel_comments;
create trigger reel_comments_sync_delete_comment_likes
  after delete on public.reel_comments
  for each row execute function public.sync_delete_comment_likes();

-- Like notifications for comments (reuse notifications.comment_id).
create unique index if not exists notifications_like_comment_unique_idx
  on public.notifications (user_id, sender_id, comment_id)
  where type = 'like'
    and comment_id is not null;

drop policy if exists notifications_insert_like on public.notifications;
create policy notifications_insert_like
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
        and comment_id is null
        and exists (
          select 1 from public.likes l
          where l.post_id = notifications.post_id and l.user_id = auth.uid()
        )
      )
      or (
        trade_id is not null
        and post_id is null
        and profile_post_id is null
        and achievement_post_id is null
        and reel_id is null
        and comment_id is null
        and exists (
          select 1 from public.trade_likes tl
          where tl.trade_id = notifications.trade_id and tl.user_id = auth.uid()
        )
      )
      or (
        profile_post_id is not null
        and comment_id is null
        and exists (
          select 1 from public.profile_post_likes ppl
          where ppl.profile_post_id = notifications.profile_post_id
            and ppl.user_id = auth.uid()
        )
      )
      or (
        achievement_post_id is not null
        and comment_id is null
        and exists (
          select 1 from public.achievement_post_likes apl
          where apl.achievement_post_id = notifications.achievement_post_id
            and apl.user_id = auth.uid()
        )
      )
      or (
        reel_id is not null
        and comment_id is null
        and exists (
          select 1 from public.reel_likes rl
          where rl.reel_id = notifications.reel_id and rl.user_id = auth.uid()
        )
      )
      or (
        comment_id is not null
        and exists (
          select 1 from public.comment_likes cl
          where cl.comment_source = case
            when notifications.post_id is not null then 'comments'
            when notifications.trade_id is not null
              and notifications.post_id is null
              and notifications.profile_post_id is null
              and notifications.achievement_post_id is null
              and notifications.reel_id is null
              then 'trade_comments'
            when notifications.profile_post_id is not null then 'profile_post_comments'
            when notifications.achievement_post_id is not null then 'achievement_post_comments'
            when notifications.reel_id is not null then 'reel_comments'
            else 'comments'
          end
            and cl.comment_id = notifications.comment_id
            and cl.user_id = auth.uid()
        )
      )
    )
  );

-- Unlike cleanup for comment likes.
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
      and profile_post_id is null
      and achievement_post_id is null
      and reel_id is null
      and comment_id is null;
  elsif tg_table_name = 'likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and post_id = old.post_id
      and profile_post_id is null
      and achievement_post_id is null
      and reel_id is null
      and comment_id is null;
  elsif tg_table_name = 'profile_post_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and profile_post_id = old.profile_post_id
      and achievement_post_id is null
      and reel_id is null
      and comment_id is null;
  elsif tg_table_name = 'achievement_post_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and achievement_post_id = old.achievement_post_id
      and reel_id is null
      and comment_id is null;
  elsif tg_table_name = 'reel_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and reel_id = old.reel_id
      and comment_id is null;
  elsif tg_table_name = 'comment_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and comment_id = old.comment_id;
  end if;

  return old;
end;
$$;

drop trigger if exists comment_likes_sync_delete_like_notification on public.comment_likes;
create trigger comment_likes_sync_delete_like_notification
  after delete on public.comment_likes
  for each row
  execute function public.sync_delete_like_notification();

-- Rate limit
create or replace function public.rate_limit_comment_likes_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.rate_limit_hit('like');
  return new;
end;
$$;

drop trigger if exists rate_limit_comment_likes_before_insert on public.comment_likes;
create trigger rate_limit_comment_likes_before_insert
  before insert on public.comment_likes
  for each row
  execute function public.rate_limit_comment_likes_before_insert();

-- Realtime
alter table public.comment_likes replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.comment_likes;
  end if;
exception
  when duplicate_object then null;
end $$;
