-- Exclude private-profile users from public discovery surfaces.
-- Followers retain access via follower-specific policies (feed posts, public trades on profile).

-- =============================================================================
-- 1. posts — public profile, owner, or follower (matches profile_posts / stories)
-- =============================================================================
drop policy if exists "posts_select_public" on public.posts;

create policy "posts_select_public"
  on public.posts
  for select
  to anon, authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.profiles p
      where p.id = posts.user_id
        and coalesce(p.is_private, false) = false
    )
    or (
      auth.uid() is not null
      and exists (
        select 1
        from public.followers f
        where f.following_id = posts.user_id
          and f.follower_id = auth.uid()
      )
    )
  );

comment on policy "posts_select_public" on public.posts is
  'Feed posts: public-profile authors, owner, or followers of private profiles.';

-- =============================================================================
-- 2. trades — public trades only from public profiles (discovery); followers of private profiles
-- =============================================================================
drop policy if exists "trades_select_public" on public.trades;

create policy "trades_select_public"
  on public.trades
  for select
  to anon, authenticated
  using (
    is_public = true
    and exists (
      select 1
      from public.profiles p
      where p.id = trades.user_id
        and coalesce(p.is_private, false) = false
    )
  );

drop policy if exists "trades_select_followed_private_profile" on public.trades;

create policy "trades_select_followed_private_profile"
  on public.trades
  for select
  to authenticated
  using (
    is_public = true
    and exists (
      select 1
      from public.profiles p
      where p.id = trades.user_id
        and coalesce(p.is_private, false) = true
    )
    and exists (
      select 1
      from public.followers f
      where f.following_id = trades.user_id
        and f.follower_id = auth.uid()
    )
  );

comment on policy "trades_select_public" on public.trades is
  'Public trades from users with public profiles (feed, explore, leaderboards).';

comment on policy "trades_select_followed_private_profile" on public.trades is
  'Followers may read public trades on private profiles they follow (profile access unchanged).';

-- =============================================================================
-- 3. Trade room discovery RPCs — exclude rooms owned by private profiles
-- =============================================================================
create or replace function public.popular_trade_rooms(p_limit int default 12)
returns table (
  id uuid,
  name text,
  description text,
  slug text,
  member_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    r.name,
    r.description,
    r.slug,
    count(m.user_id) as member_count
  from public.rooms r
  inner join public.profiles p
    on p.id = r.owner_user_id
    and coalesce(p.is_private, false) = false
  left join public.room_members m
    on m.room_id = r.id
    and m.left_at is null
  where r.owner_user_id is not null
    and coalesce(r.show_on_profile, true) = true
    and lower(trim(coalesce(r.slug, ''))) <> 'tradetraxs-beta'
  group by r.id, r.name, r.description, r.slug
  order by member_count desc, r.name asc
  limit greatest(1, least(coalesce(p_limit, 12), 50));
$$;

create or replace function public.search_public_trade_rooms(
  p_query text,
  p_limit int default 20
)
returns table (
  id uuid,
  name text,
  description text,
  slug text,
  member_count bigint,
  image_url text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    r.name,
    r.description,
    r.slug,
    count(m.user_id) as member_count,
    r.image_url
  from public.rooms r
  inner join public.profiles p
    on p.id = r.owner_user_id
    and coalesce(p.is_private, false) = false
  left join public.room_members m
    on m.room_id = r.id
    and m.left_at is null
  where r.owner_user_id is not null
    and coalesce(r.show_on_profile, true) = true
    and lower(trim(coalesce(r.slug, ''))) <> 'tradetraxs-beta'
    and trim(coalesce(p_query, '')) <> ''
    and (
      r.name ilike '%' || trim(p_query) || '%'
      or r.slug ilike '%' || trim(p_query) || '%'
    )
  group by r.id, r.name, r.description, r.slug, r.image_url
  order by member_count desc, r.name asc
  limit greatest(1, least(coalesce(p_limit, 20), 50));
$$;

comment on function public.popular_trade_rooms(int) is
  'Public discovery: profile-visible rooms with public-profile owners; excludes tradetraxs-beta.';

comment on function public.search_public_trade_rooms(text, int) is
  'Public discovery: profile-visible rooms with public-profile owners matching name or slug.';
