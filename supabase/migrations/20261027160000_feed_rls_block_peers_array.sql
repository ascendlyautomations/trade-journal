-- Phase 1 Feed RLS: replace per-row viewer_has_block_with() in SELECT policies with
-- get_active_block_peer_ids() array membership (same semantics for auth.uid() viewer).
-- Closes profile_posts direct-REST block gap. Feed RPC unchanged in this migration.

-- ---------------------------------------------------------------------------
-- Peer list for RLS: empty for guests (no user_blocks read). Authenticated
-- callers use get_active_block_peer_ids() once per statement when policies
-- use NOT (author_id = ANY (rls_viewer_block_peer_ids())) — InitPlan-friendly.
-- ---------------------------------------------------------------------------
create or replace function public.rls_viewer_block_peer_ids()
returns uuid[]
language plpgsql
stable
parallel safe
security invoker
set search_path to public
as $$
begin
  if auth.uid() is null then
    return '{}'::uuid[];
  end if;
  return coalesce(public.get_active_block_peer_ids(), '{}'::uuid[]);
end;
$$;

comment on function public.rls_viewer_block_peer_ids() is
  'Block peer ids for the current viewer; {} for guests. Used by feed RLS policies.';

revoke all on function public.rls_viewer_block_peer_ids() from public;
grant execute on function public.rls_viewer_block_peer_ids() to anon, authenticated;

-- Parity helper (NOT viewer_has_block_with for SELECT); policies inline ANY for planning.
create or replace function public.rls_passes_block_peer_check(p_author_id uuid)
returns boolean
language sql
stable
parallel safe
security invoker
set search_path to public
as $$
  select p_author_id is null
    or auth.uid() is null
    or auth.uid() = p_author_id
    or not (p_author_id = any (public.rls_viewer_block_peer_ids()));
$$;

comment on function public.rls_passes_block_peer_check(uuid) is
  'RLS block gate: true when viewer may see content from p_author_id (equivalent to NOT viewer_has_block_with for SELECT).';

revoke all on function public.rls_passes_block_peer_check(uuid) from public;
grant execute on function public.rls_passes_block_peer_check(uuid) to anon, authenticated;

comment on function public.get_active_block_peer_ids() is
  'Active block peers for auth.uid(); used by feed RPC and RLS rls_viewer_block_peer_ids.';

revoke all on function public.get_active_block_peer_ids() from public;
grant execute on function public.get_active_block_peer_ids() to authenticated;

-- ---------------------------------------------------------------------------
-- profiles (restrictive; authenticated only)
-- ---------------------------------------------------------------------------
drop policy if exists "profiles_select_hide_blocked" on public.profiles;
create policy "profiles_select_hide_blocked"
  on public.profiles
  as restrictive
  for select
  to authenticated
  using (
    id = auth.uid()
    or not (id = any (public.rls_viewer_block_peer_ids()))
    or exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  );

comment on policy "profiles_select_hide_blocked" on public.profiles is
  'Authenticated users cannot read a profile they block or that blocks them. Guests are unchanged.';

-- ---------------------------------------------------------------------------
-- posts, stories, reels, trades, achievements, achievement_posts, profile_posts
-- ---------------------------------------------------------------------------
drop policy if exists "posts_select_public" on public.posts;
create policy "posts_select_public"
  on public.posts
  for select
  to anon, authenticated
  using (
    user_id = auth.uid()
    or (
      (auth.uid() is null or not (posts.user_id = any (public.rls_viewer_block_peer_ids())))
      and (
        exists (
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
      )
    )
  );

drop policy if exists "profile_posts_select_visible" on public.profile_posts;
create policy "profile_posts_select_visible"
  on public.profile_posts
  for select
  to anon, authenticated
  using (
    user_id = auth.uid()
    or (
      (auth.uid() is null
        or not (profile_posts.user_id = any (public.rls_viewer_block_peer_ids())))
      and (
        exists (
          select 1
          from public.profiles p
          where p.id = profile_posts.user_id
            and coalesce(p.is_private, false) = false
        )
        or (
          auth.uid() is not null
          and exists (
            select 1
            from public.followers f
            where f.following_id = profile_posts.user_id
              and f.follower_id = auth.uid()
          )
        )
      )
    )
  );

comment on policy "profile_posts_select_visible" on public.profile_posts is
  'Owner, public profile, or follower read; bidirectional blocks enforced via get_active_block_peer_ids.';

drop policy if exists "stories_select_visible" on public.stories;
create policy "stories_select_visible"
  on public.stories
  for select
  to anon, authenticated
  using (
    user_id = auth.uid()
    or (
      (auth.uid() is null or not (stories.user_id = any (public.rls_viewer_block_peer_ids())))
      and (
        exists (
          select 1
          from public.profiles p
          where p.id = stories.user_id
            and coalesce(p.is_private, false) = false
        )
        or (
          auth.uid() is not null
          and exists (
            select 1
            from public.followers f
            where f.following_id = stories.user_id
              and f.follower_id = auth.uid()
          )
        )
      )
    )
  );

drop policy if exists "reels_select_visible" on public.reels;
create policy "reels_select_visible"
  on public.reels
  for select
  to anon, authenticated
  using (
    (
      trade_id is null
      and (
        user_id = auth.uid()
        or (
          (auth.uid() is null
            or not (reels.user_id = any (public.rls_viewer_block_peer_ids())))
          and (
            exists (
              select 1
              from public.profiles p
              where p.id = reels.user_id
                and coalesce(p.is_private, false) = false
            )
            or (
              auth.uid() is not null
              and exists (
                select 1
                from public.followers f
                where f.following_id = reels.user_id
                  and f.follower_id = auth.uid()
              )
            )
          )
        )
      )
    )
    or (
      trade_id is not null
      and user_id = auth.uid()
    )
    or (
      trade_id is not null
      and not (reels.user_id = any (public.rls_viewer_block_peer_ids()))
      and exists (
        select 1
        from public.trades t
        join public.profiles p on p.id = t.user_id
        where t.id = reels.trade_id
          and t.is_public = true
          and coalesce(p.is_private, false) = false
      )
    )
    or (
      trade_id is not null
      and auth.uid() is not null
      and not (reels.user_id = any (public.rls_viewer_block_peer_ids()))
      and exists (
        select 1
        from public.trades t
        join public.profiles p on p.id = t.user_id
        where t.id = reels.trade_id
          and t.is_public = true
          and coalesce(p.is_private, false) = true
      )
      and exists (
        select 1
        from public.trades t
        join public.followers f on f.following_id = t.user_id
        where t.id = reels.trade_id
          and f.follower_id = auth.uid()
      )
    )
  );

drop policy if exists "trades_select_public" on public.trades;
create policy "trades_select_public"
  on public.trades
  for select
  to anon, authenticated
  using (
    coalesce(is_public, false) = true
    and (auth.uid() is null or not (trades.user_id = any (public.rls_viewer_block_peer_ids())))
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
    and not (trades.user_id = any (public.rls_viewer_block_peer_ids()))
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

drop policy if exists "achievements_select_public" on public.achievements;
create policy "achievements_select_public"
  on public.achievements
  for select
  to anon, authenticated
  using (
    coalesce(is_public, false) = true
    and (auth.uid() is null
      or not (achievements.user_id = any (public.rls_viewer_block_peer_ids())))
    and (
      exists (
        select 1
        from public.profiles p
        where p.id = achievements.user_id
          and coalesce(p.is_private, false) = false
      )
      or (
        auth.uid() is not null
        and exists (
          select 1
          from public.followers f
          where f.following_id = achievements.user_id
            and f.follower_id = auth.uid()
        )
      )
    )
  );

drop policy if exists "achievement_posts_select_authenticated" on public.achievement_posts;
create policy "achievement_posts_select_authenticated"
  on public.achievement_posts
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.achievements a
      where a.id = achievement_posts.achievement_id
        and (
          a.user_id = auth.uid()
          or (
            coalesce(a.is_public, false) = true
            and not (a.user_id = any (public.rls_viewer_block_peer_ids()))
            and (
              exists (
                select 1
                from public.profiles p
                where p.id = a.user_id
                  and coalesce(p.is_private, false) = false
              )
              or exists (
                select 1
                from public.followers f
                where f.following_id = a.user_id
                  and f.follower_id = auth.uid()
              )
            )
          )
        )
    )
  );
