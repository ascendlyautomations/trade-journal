-- Isolated feed cand benchmark schema (not production). SECURITY patterns mirror invoker feed reads.

create extension if not exists pgcrypto;

create schema if not exists auth;

create or replace function auth.uid()
returns uuid
language sql
stable
set search_path = public
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create table public.profiles (
  id uuid primary key,
  username text not null,
  is_private boolean not null default false,
  avatar_url text
);

create table public.followers (
  id uuid primary key default gen_random_uuid(),
  follower_id uuid not null,
  following_id uuid not null,
  created_at timestamptz not null default now(),
  unique (follower_id, following_id)
);

create table public.user_blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null,
  blocked_id uuid not null,
  created_at timestamptz not null default now(),
  unique (blocker_id, blocked_id)
);

create table public.trades (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  is_public boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  trade_id uuid references public.trades (id),
  created_at timestamptz not null,
  pnl numeric,
  rr numeric,
  image_url text,
  image_crop jsonb
);

create table public.profile_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  content text,
  created_at timestamptz not null,
  image_url text,
  image_crop jsonb
);

create table public.achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  title text not null default 'badge',
  is_public boolean not null default true
);

create table public.achievement_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  achievement_id uuid not null references public.achievements (id),
  created_at timestamptz not null,
  metadata jsonb
);

create table public.reels (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  trade_id uuid references public.trades (id),
  created_at timestamptz not null,
  caption text,
  visibility text not null default 'public'
);

create or replace function public.viewer_has_block_with(p_author_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
    from public.user_blocks ub
    where (ub.blocker_id = auth.uid() and ub.blocked_id = p_author_id)
       or (ub.blocker_id = p_author_id and ub.blocked_id = auth.uid())
  );
$$;

create or replace function public.get_active_block_peer_ids()
returns uuid[]
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(array_agg(distinct peer_id), '{}'::uuid[])
  from (
    select ub.blocked_id as peer_id
    from public.user_blocks ub
    where ub.blocker_id = auth.uid()
    union
    select ub.blocker_id
    from public.user_blocks ub
    where ub.blocked_id = auth.uid()
  ) s;
$$;

alter table public.posts enable row level security;
alter table public.profile_posts enable row level security;
alter table public.achievement_posts enable row level security;
alter table public.reels enable row level security;
alter table public.profiles enable row level security;

create policy posts_select_visible on public.posts for select to authenticated
using (
  user_id = auth.uid()
  or (
    not public.viewer_has_block_with(posts.user_id)
    and (
      exists (
        select 1 from public.profiles p
        where p.id = posts.user_id and coalesce(p.is_private, false) = false
      )
      or exists (
        select 1 from public.followers f
        where f.following_id = posts.user_id and f.follower_id = auth.uid()
      )
    )
  )
);

create policy profile_posts_select_visible on public.profile_posts for select to authenticated
using (
  user_id = auth.uid()
  or (
    not public.viewer_has_block_with(profile_posts.user_id)
    and (
      exists (
        select 1 from public.profiles p
        where p.id = profile_posts.user_id and coalesce(p.is_private, false) = false
      )
      or exists (
        select 1 from public.followers f
        where f.following_id = profile_posts.user_id and f.follower_id = auth.uid()
      )
    )
  )
);

create policy achievement_posts_select_visible on public.achievement_posts for select to authenticated
using (
  user_id = auth.uid()
  or (
    not public.viewer_has_block_with(achievement_posts.user_id)
    and exists (
      select 1 from public.achievements a
      where a.id = achievement_posts.achievement_id and coalesce(a.is_public, true) = true
    )
    and (
      exists (
        select 1 from public.profiles p
        where p.id = achievement_posts.user_id and coalesce(p.is_private, false) = false
      )
      or exists (
        select 1 from public.followers f
        where f.following_id = achievement_posts.user_id and f.follower_id = auth.uid()
      )
    )
  )
);

create policy reels_select_visible on public.reels for select to authenticated
using (
  user_id = auth.uid()
  or (
    not public.viewer_has_block_with(reels.user_id)
    and (
      exists (
        select 1 from public.profiles p
        where p.id = reels.user_id and coalesce(p.is_private, false) = false
      )
      or exists (
        select 1 from public.followers f
        where f.following_id = reels.user_id and f.follower_id = auth.uid()
      )
    )
  )
);

create policy profiles_select on public.profiles for select to authenticated using (true);

do $$ begin
  create role authenticated;
exception
  when duplicate_object then null;
end $$;

grant usage on schema public to authenticated;
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant select on all tables in schema public to authenticated;
grant execute on function public.viewer_has_block_with(uuid) to authenticated;
grant execute on function public.get_active_block_peer_ids() to authenticated;
