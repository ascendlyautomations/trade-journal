-- Social achievement posts: feed entries + engagement (mirrors profile_posts pattern).

create table if not exists public.achievement_posts (
  id uuid primary key default gen_random_uuid(),
  achievement_id uuid not null unique references public.achievements (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists achievement_posts_user_id_created_at_idx
  on public.achievement_posts (user_id, created_at desc);

create index if not exists achievement_posts_created_at_idx
  on public.achievement_posts (created_at desc);

comment on table public.achievement_posts is
  'Social feed row for an achievement unlock; one row per achievement.';
comment on column public.achievement_posts.metadata is
  'Extensible snapshot (broker, profit, streak, percentile, etc.) without schema churn.';

alter table public.achievement_posts enable row level security;

create policy achievement_posts_select_authenticated
  on public.achievement_posts
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.achievements a
      where a.id = achievement_posts.achievement_id
        and (a.user_id = auth.uid() or a.is_public = true)
    )
  );

create policy achievement_posts_select_anon_public
  on public.achievement_posts
  for select
  to anon
  using (
    exists (
      select 1
      from public.achievements a
      where a.id = achievement_posts.achievement_id
        and a.is_public = true
    )
  );

create policy achievement_posts_insert_own
  on public.achievement_posts
  for insert
  to authenticated
  with check (auth.uid() = user_id);

grant select on table public.achievement_posts to authenticated, anon;

-- Auto-create social post when an achievement is recorded.
create or replace function public.create_achievement_post_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.achievement_posts (achievement_id, user_id, metadata)
  values (
    new.id,
    new.user_id,
    jsonb_build_object(
      'achievement_type', new.achievement_type,
      'title', new.title,
      'badge_key', new.badge_key,
      'value_numeric', new.value_numeric,
      'value_text', new.value_text
    ) || coalesce(new.metadata, '{}'::jsonb)
  )
  on conflict (achievement_id) do nothing;

  return new;
end;
$$;

drop trigger if exists achievements_create_social_post on public.achievements;
create trigger achievements_create_social_post
  after insert on public.achievements
  for each row
  execute function public.create_achievement_post_on_insert();

-- Backfill social posts for existing achievements.
insert into public.achievement_posts (achievement_id, user_id, metadata)
select
  a.id,
  a.user_id,
  jsonb_build_object(
    'achievement_type', a.achievement_type,
    'title', a.title,
    'badge_key', a.badge_key,
    'value_numeric', a.value_numeric,
    'value_text', a.value_text
  ) || coalesce(a.metadata, '{}'::jsonb)
from public.achievements a
on conflict (achievement_id) do nothing;

-- Likes & comments
create table if not exists public.achievement_post_likes (
  id uuid primary key default gen_random_uuid(),
  achievement_post_id uuid not null references public.achievement_posts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (achievement_post_id, user_id)
);

create table if not exists public.achievement_post_comments (
  id uuid primary key default gen_random_uuid(),
  achievement_post_id uuid not null references public.achievement_posts (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  content text not null,
  parent_comment_id uuid null references public.achievement_post_comments (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists achievement_post_likes_post_id_idx
  on public.achievement_post_likes (achievement_post_id);

create index if not exists achievement_post_comments_post_id_idx
  on public.achievement_post_comments (achievement_post_id);

alter table public.achievement_post_likes enable row level security;
alter table public.achievement_post_comments enable row level security;

create policy achievement_post_likes_insert_own
  on public.achievement_post_likes for insert to authenticated
  with check (auth.uid() = user_id);

create policy achievement_post_likes_delete_own
  on public.achievement_post_likes for delete to authenticated
  using (auth.uid() = user_id);

create policy achievement_post_likes_select_authenticated
  on public.achievement_post_likes for select to authenticated using (true);

create policy achievement_post_comments_select_authenticated
  on public.achievement_post_comments for select to authenticated using (true);

create policy achievement_post_comments_insert_own
  on public.achievement_post_comments for insert to authenticated
  with check (auth.uid() = user_id);

create policy achievement_post_comments_delete_own
  on public.achievement_post_comments for delete to authenticated
  using (auth.uid() = user_id);

grant select, insert, delete on table public.achievement_post_likes to authenticated;
grant select, insert, delete on table public.achievement_post_comments to authenticated;

-- Notifications
alter table public.notifications
  add column if not exists achievement_post_id uuid
  references public.achievement_posts (id) on delete cascade;

create index if not exists notifications_achievement_post_id_idx
  on public.notifications (achievement_post_id)
  where achievement_post_id is not null;

-- DM share target
alter table public.messages
  add column if not exists achievement_post_id uuid
  references public.achievement_posts (id) on delete cascade;

create index if not exists messages_achievement_post_id_idx
  on public.messages (achievement_post_id)
  where achievement_post_id is not null;

-- Notification insert policies (extend like + comment checks)
drop policy if exists "notifications_insert_like" on public.notifications;
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
          select 1 from public.likes l
          where l.post_id = notifications.post_id and l.user_id = auth.uid()
        )
      )
      or (
        trade_id is not null
        and post_id is null
        and profile_post_id is null
        and achievement_post_id is null
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
    )
  );

drop policy if exists "notifications_insert_comment" on public.notifications;
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
          select 1 from public.comments c
          where c.post_id = notifications.post_id and c.user_id = auth.uid()
        )
      )
      or (
        trade_id is not null
        and post_id is null
        and profile_post_id is null
        and achievement_post_id is null
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
    )
  );

-- Like dedupe index
create unique index if not exists notifications_like_achievement_post_unique_idx
  on public.notifications (user_id, sender_id, achievement_post_id)
  where type = 'like'
    and achievement_post_id is not null;

-- Unlike cleanup trigger extension
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
      and achievement_post_id is null;
  elsif tg_table_name = 'likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and post_id = old.post_id
      and profile_post_id is null
      and achievement_post_id is null;
  elsif tg_table_name = 'profile_post_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and profile_post_id = old.profile_post_id
      and achievement_post_id is null;
  elsif tg_table_name = 'achievement_post_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and achievement_post_id = old.achievement_post_id;
  end if;

  return old;
end;
$$;

drop trigger if exists achievement_post_likes_sync_delete_like_notification on public.achievement_post_likes;
create trigger achievement_post_likes_sync_delete_like_notification
  after delete on public.achievement_post_likes
  for each row
  execute function public.sync_delete_like_notification();

-- Rate limits
create or replace function public.rate_limit_achievement_post_likes_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;
  perform public.rate_limit_hit('like');
  return new;
end;
$$;

create or replace function public.rate_limit_achievement_post_comments_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;
  perform public.rate_limit_hit('comment');
  return new;
end;
$$;

drop trigger if exists rate_limit_achievement_post_likes_before_insert on public.achievement_post_likes;
create trigger rate_limit_achievement_post_likes_before_insert
  before insert on public.achievement_post_likes
  for each row
  execute function public.rate_limit_achievement_post_likes_before_insert();

drop trigger if exists rate_limit_achievement_post_comments_before_insert on public.achievement_post_comments;
create trigger rate_limit_achievement_post_comments_before_insert
  before insert on public.achievement_post_comments
  for each row
  execute function public.rate_limit_achievement_post_comments_before_insert();
