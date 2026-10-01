-- Hide internal profile columns from direct reads, enforce bidirectional blocks
-- on public content reads, and hide private-profile achievements from strangers.
--
-- Owner and service-role paths keep the private columns. profile_reader_row is
-- the security-definer load used by profile bootstrap so SELECT * no longer
-- needs table column privileges. Block semantics match feed/explore:
-- users_have_active_block is bidirectional, and guests (no auth.uid()) are
-- unaffected.

-- ---------------------------------------------------------------------------
-- Owner private fields. Direct callers who are not the row owner get null.
-- ---------------------------------------------------------------------------

create or replace function public.profile_owner_private_fields()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'locked_account_id', p.locked_account_id,
    'locked_account_name', p.locked_account_name,
    'locked_account_number', p.locked_account_number,
    'locked_account_size', p.locked_account_size,
    'locked_account_type', p.locked_account_type,
    'stripe_customer_id', p.stripe_customer_id,
    'stripe_price_id', p.stripe_price_id,
    'referral_earnings', p.referral_earnings,
    'billing_interval', p.billing_interval
  )
  from public.profiles p
  where p.id = auth.uid();
$$;

comment on function public.profile_owner_private_fields() is
  'Owner-only locked account and billing fields. Non-owners receive null.';

revoke all on function public.profile_owner_private_fields() from public;
grant execute on function public.profile_owner_private_fields() to authenticated;

-- ---------------------------------------------------------------------------
-- Block probe that cannot be used to test arbitrary user pairs.
-- Guests always get false.
-- ---------------------------------------------------------------------------

create or replace function public.viewer_has_block_with(p_author_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and p_author_id is not null
    and auth.uid() is distinct from p_author_id
    and public.users_have_active_block(auth.uid(), p_author_id);
$$;

comment on function public.viewer_has_block_with(uuid) is
  'True when the current user and p_author_id block each other in either direction.';

revoke all on function public.viewer_has_block_with(uuid) from public;
grant execute on function public.viewer_has_block_with(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Profile row for bootstrap. Definer so private columns can be read, then
-- stripped unless the caller owns the row. Blocked peers receive null.
-- ---------------------------------------------------------------------------

create or replace function public.profile_reader_row(p_identifier text)
returns public.profiles
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v public.profiles%rowtype;
begin
  if p_identifier is null or trim(p_identifier) = '' then
    return null;
  end if;

  if p_identifier ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into v
    from public.profiles p
    where p.id = p_identifier::uuid;
  else
    select * into v
    from public.profiles p
    where lower(trim(p.username)) = lower(trim(p_identifier));
  end if;

  if v.id is null then
    return null;
  end if;

  if public.viewer_has_block_with(v.id) then
    return null;
  end if;

  if auth.uid() is distinct from v.id then
    v.locked_account_id := null;
    v.locked_account_name := null;
    v.locked_account_number := null;
    v.locked_account_size := null;
    v.locked_account_type := null;
    v.stripe_customer_id := null;
    v.stripe_price_id := null;
    v.referral_earnings := null;
    v.billing_interval := null;
  end if;

  return v;
end;
$$;

comment on function public.profile_reader_row(text) is
  'Profile bootstrap row. Non-owners do not receive billing or locked-account columns. Blocked peers receive null.';

revoke all on function public.profile_reader_row(text) from public;
grant execute on function public.profile_reader_row(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Stop invoker RPCs from selecting revoked columns.
-- ---------------------------------------------------------------------------

do $mig$
declare
  src text;
  updated text;
begin
  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_profile_bootstrap'
    and pg_get_function_identity_arguments(p.oid) =
      'p_identifier text, p_initial_tab text, p_limit integer, p_cursor text';

  updated := replace(
    src,
    $old$  if p_identifier ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into v_profile from public.profiles p where p.id = p_identifier::uuid;
  else
    select * into v_profile
    from public.profiles p
    where lower(trim(p.username)) = lower(trim(p_identifier));
  end if;$old$,
    $new$  v_profile := public.profile_reader_row(p_identifier);$new$
  );
  if updated = src and position('profile_reader_row' in src) = 0 then
    raise exception 'rpc_v1_profile_bootstrap profile lookup was not found';
  end if;
  if updated <> src then
    execute updated;
  end if;

  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_session_bootstrap'
    and pg_get_function_identity_arguments(p.oid) = '';

  updated := replace(
    src,
    $old$'stripe_customer_id', p.stripe_customer_id$old$,
    $new$'stripe_customer_id', (select public.profile_owner_private_fields() ->> 'stripe_customer_id')$new$
  );
  if updated = src and position('profile_owner_private_fields' in src) = 0 then
    raise exception 'rpc_v1_session_bootstrap stripe_customer_id read was not found';
  end if;
  if updated <> src then
    execute updated;
  end if;
end
$mig$;

-- ---------------------------------------------------------------------------
-- Column boundary. Public discovery columns stay selectable.
-- ---------------------------------------------------------------------------

-- Table SELECT overrides a column-only REVOKE. The follow-up migration
-- 20261001073000 replaces table SELECT with the public column list.
revoke select (
  locked_account_id,
  locked_account_name,
  locked_account_number,
  locked_account_size,
  locked_account_type,
  stripe_customer_id,
  stripe_price_id,
  referral_earnings,
  billing_interval
) on table public.profiles from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Bidirectional block on direct profile reads (search and embeds).
-- Guests are not in this policy, so public discovery stays open.
-- ---------------------------------------------------------------------------

drop policy if exists "profiles_select_hide_blocked" on public.profiles;
create policy "profiles_select_hide_blocked"
  on public.profiles
  as restrictive
  for select
  to authenticated
  using (
    id = auth.uid()
    or not public.viewer_has_block_with(id)
    or exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  );

comment on policy "profiles_select_hide_blocked" on public.profiles is
  'Authenticated users cannot read a profile they block or that blocks them. Guests are unchanged.';

-- ---------------------------------------------------------------------------
-- Posts, stories, reels, public trades: same block rule as feed bootstrap.
-- Owner rows and DM-shared trades are unchanged.
-- ---------------------------------------------------------------------------

drop policy if exists "posts_select_public" on public.posts;
create policy "posts_select_public"
  on public.posts
  for select
  to anon, authenticated
  using (
    user_id = auth.uid()
    or (
      not public.viewer_has_block_with(posts.user_id)
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

drop policy if exists "stories_select_visible" on public.stories;
create policy "stories_select_visible"
  on public.stories
  for select
  to anon, authenticated
  using (
    user_id = auth.uid()
    or (
      not public.viewer_has_block_with(stories.user_id)
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
          not public.viewer_has_block_with(reels.user_id)
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
      and not public.viewer_has_block_with(reels.user_id)
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
      and not public.viewer_has_block_with(reels.user_id)
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
    and not public.viewer_has_block_with(trades.user_id)
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
    and not public.viewer_has_block_with(trades.user_id)
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

-- ---------------------------------------------------------------------------
-- Achievements follow the private-profile model, and blocks hide them too.
-- ---------------------------------------------------------------------------

drop policy if exists "achievements_select_public" on public.achievements;
create policy "achievements_select_public"
  on public.achievements
  for select
  to anon, authenticated
  using (
    coalesce(is_public, false) = true
    and not public.viewer_has_block_with(achievements.user_id)
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

drop policy if exists "achievement_posts_select_anon_public" on public.achievement_posts;
create policy "achievement_posts_select_anon_public"
  on public.achievement_posts
  for select
  to anon
  using (
    exists (
      select 1
      from public.achievements a
      join public.profiles p on p.id = a.user_id
      where a.id = achievement_posts.achievement_id
        and coalesce(a.is_public, false) = true
        and coalesce(p.is_private, false) = false
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
            and not public.viewer_has_block_with(a.user_id)
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
