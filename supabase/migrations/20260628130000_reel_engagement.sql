-- Reel social engagement: likes, comments, notifications, DM share.

-- =============================================================================
-- Likes & comments
-- =============================================================================

create table if not exists public.reel_likes (
  id uuid primary key default gen_random_uuid(),
  reel_id uuid not null references public.reels (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (reel_id, user_id)
);

create table if not exists public.reel_comments (
  id uuid primary key default gen_random_uuid(),
  reel_id uuid not null references public.reels (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  content text not null,
  parent_comment_id uuid null references public.reel_comments (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists reel_likes_reel_id_idx
  on public.reel_likes (reel_id);

create index if not exists reel_comments_reel_id_idx
  on public.reel_comments (reel_id);

alter table public.reel_likes enable row level security;
alter table public.reel_comments enable row level security;

create policy reel_likes_insert_own
  on public.reel_likes for insert to authenticated
  with check (auth.uid() = user_id);

create policy reel_likes_delete_own
  on public.reel_likes for delete to authenticated
  using (auth.uid() = user_id);

create policy reel_likes_select_authenticated
  on public.reel_likes for select to authenticated using (true);

create policy reel_comments_select_authenticated
  on public.reel_comments for select to authenticated using (true);

create policy reel_comments_insert_own
  on public.reel_comments for insert to authenticated
  with check (auth.uid() = user_id);

create policy reel_comments_delete_own
  on public.reel_comments for delete to authenticated
  using (auth.uid() = user_id);

grant select, insert, delete on table public.reel_likes to authenticated;
grant select, insert, delete on table public.reel_comments to authenticated;

-- =============================================================================
-- Notifications & messages
-- =============================================================================

alter table public.notifications
  add column if not exists reel_id uuid
  references public.reels (id) on delete cascade;

create index if not exists notifications_reel_id_idx
  on public.notifications (reel_id)
  where reel_id is not null;

alter table public.messages
  add column if not exists reel_id uuid
  references public.reels (id) on delete cascade;

create index if not exists messages_reel_id_idx
  on public.messages (reel_id)
  where reel_id is not null;

create unique index if not exists notifications_like_reel_unique_idx
  on public.notifications (user_id, sender_id, reel_id)
  where type = 'like'
    and reel_id is not null;

-- =============================================================================
-- Notification policies (extend like + comment)
-- =============================================================================

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
        and exists (
          select 1 from public.trade_likes tl
          where tl.trade_id = notifications.trade_id and tl.user_id = auth.uid()
        )
      )
      or (
        profile_post_id is not null
        and exists (
          select 1 from public.profile_post_likes ppl
          where ppl.profile_post_id = notifications.profile_post_id
            and ppl.user_id = auth.uid()
        )
      )
      or (
        achievement_post_id is not null
        and exists (
          select 1 from public.achievement_post_likes apl
          where apl.achievement_post_id = notifications.achievement_post_id
            and apl.user_id = auth.uid()
        )
      )
      or (
        reel_id is not null
        and exists (
          select 1 from public.reel_likes rl
          where rl.reel_id = notifications.reel_id and rl.user_id = auth.uid()
        )
      )
    )
  );

drop policy if exists notifications_insert_comment on public.notifications;
create policy notifications_insert_comment
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
          select 1 from public.comments c
          where c.post_id = notifications.post_id and c.user_id = auth.uid()
        )
      )
      or (
        trade_id is not null
        and post_id is null
        and profile_post_id is null
        and achievement_post_id is null
        and reel_id is null
        and exists (
          select 1 from public.trade_comments tc
          where tc.trade_id = notifications.trade_id and tc.user_id = auth.uid()
        )
      )
      or (
        profile_post_id is not null
        and exists (
          select 1 from public.profile_post_comments ppc
          where ppc.profile_post_id = notifications.profile_post_id
            and ppc.user_id = auth.uid()
        )
      )
      or (
        achievement_post_id is not null
        and exists (
          select 1 from public.achievement_post_comments apc
          where apc.achievement_post_id = notifications.achievement_post_id
            and apc.user_id = auth.uid()
        )
      )
      or (
        reel_id is not null
        and exists (
          select 1 from public.reel_comments rc
          where rc.reel_id = notifications.reel_id and rc.user_id = auth.uid()
        )
      )
    )
  );

-- Unlike cleanup
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
      and reel_id is null;
  elsif tg_table_name = 'likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and post_id = old.post_id
      and profile_post_id is null
      and achievement_post_id is null
      and reel_id is null;
  elsif tg_table_name = 'profile_post_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and profile_post_id = old.profile_post_id
      and achievement_post_id is null
      and reel_id is null;
  elsif tg_table_name = 'achievement_post_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and achievement_post_id = old.achievement_post_id
      and reel_id is null;
  elsif tg_table_name = 'reel_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and reel_id = old.reel_id;
  end if;

  return old;
end;
$$;

drop trigger if exists reel_likes_sync_delete_like_notification on public.reel_likes;
create trigger reel_likes_sync_delete_like_notification
  after delete on public.reel_likes
  for each row
  execute function public.sync_delete_like_notification();

-- Rate limits
create or replace function public.rate_limit_reel_likes_before_insert()
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

create or replace function public.rate_limit_reel_comments_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.rate_limit_hit('comment');
  return new;
end;
$$;

drop trigger if exists rate_limit_reel_likes_before_insert on public.reel_likes;
create trigger rate_limit_reel_likes_before_insert
  before insert on public.reel_likes
  for each row
  execute function public.rate_limit_reel_likes_before_insert();

drop trigger if exists rate_limit_reel_comments_before_insert on public.reel_comments;
create trigger rate_limit_reel_comments_before_insert
  before insert on public.reel_comments
  for each row
  execute function public.rate_limit_reel_comments_before_insert();
