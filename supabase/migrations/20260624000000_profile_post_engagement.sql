-- Profile post likes & comments (mirrors trade_likes / trade_comments).

create table if not exists public.profile_post_likes (
  id uuid primary key default gen_random_uuid(),
  profile_post_id uuid not null references public.profile_posts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (profile_post_id, user_id)
);

create table if not exists public.profile_post_comments (
  id uuid primary key default gen_random_uuid(),
  profile_post_id uuid not null references public.profile_posts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  content text not null,
  parent_comment_id uuid null references public.profile_post_comments (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists profile_post_likes_profile_post_id_idx
  on public.profile_post_likes (profile_post_id);

create index if not exists profile_post_comments_profile_post_id_idx
  on public.profile_post_comments (profile_post_id);

create index if not exists profile_post_comments_parent_comment_id_idx
  on public.profile_post_comments (parent_comment_id)
  where parent_comment_id is not null;

alter table public.profile_post_likes enable row level security;
alter table public.profile_post_comments enable row level security;

create policy profile_post_likes_insert_own
  on public.profile_post_likes
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy profile_post_likes_delete_own
  on public.profile_post_likes
  for delete
  to authenticated
  using (auth.uid() = user_id);

create policy profile_post_likes_select_authenticated
  on public.profile_post_likes
  for select
  to authenticated
  using (true);

create policy profile_post_comments_select_authenticated
  on public.profile_post_comments
  for select
  to authenticated
  using (true);

create policy profile_post_comments_insert_own
  on public.profile_post_comments
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy profile_post_comments_delete_own
  on public.profile_post_comments
  for delete
  to authenticated
  using (auth.uid() = user_id);

grant select, insert, delete on table public.profile_post_likes to authenticated;
grant select, insert, delete on table public.profile_post_comments to authenticated;

-- Notifications: link profile post engagement.
alter table public.notifications
  add column if not exists profile_post_id uuid references public.profile_posts (id) on delete cascade;

create index if not exists notifications_profile_post_id_idx
  on public.notifications (profile_post_id)
  where profile_post_id is not null;

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
      or (
        profile_post_id is not null
        and exists (
          select 1
          from public.profile_post_likes ppl
          where ppl.profile_post_id = notifications.profile_post_id
            and ppl.user_id = auth.uid()
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
      or (
        profile_post_id is not null
        and exists (
          select 1
          from public.profile_post_comments ppc
          where ppc.profile_post_id = notifications.profile_post_id
            and ppc.user_id = auth.uid()
        )
      )
    )
  );

-- Rate limits (same shadow-mode pattern as trade engagement).
create or replace function public.rate_limit_profile_post_likes_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return NEW;
  end if;

  perform public.rate_limit_hit('like');
  return NEW;
end;
$$;

create or replace function public.rate_limit_profile_post_comments_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return NEW;
  end if;

  perform public.rate_limit_hit('comment');
  return NEW;
end;
$$;

drop trigger if exists rate_limit_profile_post_likes_before_insert on public.profile_post_likes;
create trigger rate_limit_profile_post_likes_before_insert
  before insert on public.profile_post_likes
  for each row
  execute function public.rate_limit_profile_post_likes_before_insert();

drop trigger if exists rate_limit_profile_post_comments_before_insert on public.profile_post_comments;
create trigger rate_limit_profile_post_comments_before_insert
  before insert on public.profile_post_comments
  for each row
  execute function public.rate_limit_profile_post_comments_before_insert();
