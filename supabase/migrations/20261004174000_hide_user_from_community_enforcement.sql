-- Admin community visibility. Separate from ban, suspension, private profiles, and deletion.
-- Hidden accounts keep their rows and can still use their own journal. Other users cannot discover them.

alter table public.profiles
  add column if not exists is_hidden_from_community boolean not null default false;

comment on column public.profiles.is_hidden_from_community is
  'Admin-only. When true, other users cannot discover or read this profile. The owner can still use the account. Does not delete data.';

revoke select (is_hidden_from_community) on table public.profiles from anon, authenticated;
grant update (is_hidden_from_community) on table public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- One visibility rule for community reads.
-- Owner and platform admins can see the profile. Everyone else cannot when hidden.
-- Private-profile and block rules stay in their existing policies.
-- ---------------------------------------------------------------------------

create or replace function public.profile_is_visible_to_viewer(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_profile_id is not null
    and exists (
      select 1
      from public.profiles p
      where p.id = p_profile_id
        and (
          p.id is not distinct from auth.uid()
          or coalesce(p.is_hidden_from_community, false) = false
          or exists (
            select 1
            from public.admin_users au
            where au.user_id = auth.uid()
          )
        )
    );
$$;

comment on function public.profile_is_visible_to_viewer(uuid) is
  'True for the profile owner, a platform admin, or any profile that is not hidden from the community.';

revoke all on function public.profile_is_visible_to_viewer(uuid) from public;
grant execute on function public.profile_is_visible_to_viewer(uuid) to anon, authenticated;

-- Normal users cannot set the flag on themselves. Admins and service_role already pass the trigger.
create or replace function public.profiles_reject_privileged_self_update()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if exists (
    select 1
    from public.admin_users au
    where au.user_id = auth.uid()
  ) then
    return new;
  end if;

  if auth.uid() is null or auth.uid() <> old.id then
    return new;
  end if;

  if new.referred_by is distinct from old.referred_by then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.is_pro is distinct from old.is_pro then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.creator_access is distinct from old.creator_access then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.creator_code is distinct from old.creator_code then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.creator_granted_at is distinct from old.creator_granted_at then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.is_beta_tester is distinct from old.is_beta_tester then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.use_free_tier is distinct from old.use_free_tier then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.trial_end is distinct from old.trial_end then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.has_used_csv_import is distinct from old.has_used_csv_import then
    if coalesce(old.has_used_csv_import, false) = true then
      raise exception 'Protected profile fields cannot be modified.';
    end if;
    if coalesce(new.has_used_csv_import, false) = false then
      raise exception 'Protected profile fields cannot be modified.';
    end if;
  end if;

  if new.last_csv_import_at is distinct from old.last_csv_import_at then
    if old.last_csv_import_at is not null
       and (
         new.last_csv_import_at is null
         or new.last_csv_import_at <= old.last_csv_import_at
       ) then
      raise exception 'Protected profile fields cannot be modified.';
    end if;
  end if;

  if new.subscription_status is distinct from old.subscription_status then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.stripe_customer_id is distinct from old.stripe_customer_id then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.stripe_price_id is distinct from old.stripe_price_id then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.billing_interval is distinct from old.billing_interval then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.cancel_at_period_end is distinct from old.cancel_at_period_end then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.cancel_at is distinct from old.cancel_at then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.current_period_end is distinct from old.current_period_end then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.referral_earnings is distinct from old.referral_earnings then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.referral_count is distinct from old.referral_count then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.is_banned is distinct from old.is_banned then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.banned_by is distinct from old.banned_by then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.banned_at is distinct from old.banned_at then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.banned_reason is distinct from old.banned_reason then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.is_hidden_from_community is distinct from old.is_hidden_from_community then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  return new;
end;
$$;

-- Direct profile reads (search, embeds, and security-invoker RPCs).
drop policy if exists profiles_select_hide_from_community on public.profiles;
create policy profiles_select_hide_from_community
  on public.profiles
  as restrictive
  for select
  to anon, authenticated
  using (public.profile_is_visible_to_viewer(id));

comment on policy profiles_select_hide_from_community on public.profiles is
  'Hidden profiles are readable by the owner and platform admins. Other viewers get no row.';

-- Community content. Owner rows stay readable. Follows do not reveal a hidden account.
drop policy if exists posts_hide_from_community on public.posts;
create policy posts_hide_from_community
  on public.posts as restrictive for select to anon, authenticated
  using (public.profile_is_visible_to_viewer(user_id));

drop policy if exists stories_hide_from_community on public.stories;
create policy stories_hide_from_community
  on public.stories as restrictive for select to anon, authenticated
  using (public.profile_is_visible_to_viewer(user_id));

drop policy if exists reels_hide_from_community on public.reels;
create policy reels_hide_from_community
  on public.reels as restrictive for select to anon, authenticated
  using (public.profile_is_visible_to_viewer(user_id));

drop policy if exists trades_hide_from_community on public.trades;
create policy trades_hide_from_community
  on public.trades as restrictive for select to anon, authenticated
  using (public.profile_is_visible_to_viewer(user_id));

drop policy if exists achievements_hide_from_community on public.achievements;
create policy achievements_hide_from_community
  on public.achievements as restrictive for select to anon, authenticated
  using (public.profile_is_visible_to_viewer(user_id));

drop policy if exists achievement_posts_hide_from_community on public.achievement_posts;
create policy achievement_posts_hide_from_community
  on public.achievement_posts as restrictive for select to anon, authenticated
  using (public.profile_is_visible_to_viewer(user_id));

drop policy if exists profile_posts_hide_from_community on public.profile_posts;
create policy profile_posts_hide_from_community
  on public.profile_posts as restrictive for select to anon, authenticated
  using (public.profile_is_visible_to_viewer(user_id));

drop policy if exists comments_hide_from_community on public.comments;
create policy comments_hide_from_community
  on public.comments as restrictive for select to anon, authenticated
  using (public.profile_is_visible_to_viewer(user_id));

drop policy if exists likes_hide_from_community on public.likes;
create policy likes_hide_from_community
  on public.likes as restrictive for select to anon, authenticated
  using (public.profile_is_visible_to_viewer(user_id));

drop policy if exists followers_hide_from_community on public.followers;
create policy followers_hide_from_community
  on public.followers as restrictive for select to anon, authenticated
  using (
    public.profile_is_visible_to_viewer(follower_id)
    and public.profile_is_visible_to_viewer(following_id)
  );

drop policy if exists room_members_hide_from_community on public.room_members;
create policy room_members_hide_from_community
  on public.room_members as restrictive for select to authenticated
  using (
    public.profile_is_visible_to_viewer(user_id)
    or public.can_manage_trade_room(room_id, auth.uid())
  );

drop policy if exists room_messages_hide_from_community on public.room_messages;
create policy room_messages_hide_from_community
  on public.room_messages as restrictive for select to authenticated
  using (public.profile_is_visible_to_viewer(user_id));

-- Direct messages stay readable by the existing participants. New messages to a
-- hidden account are refused in recipient_allows_dm. Rows are not deleted.
drop policy if exists messages_hide_from_community on public.messages;

drop policy if exists notifications_hide_from_community on public.notifications;
create policy notifications_hide_from_community
  on public.notifications as restrictive for select to authenticated
  using (
    sender_id is null
    or public.profile_is_visible_to_viewer(sender_id)
  );

do $policies$
declare
  community_table text;
begin
  foreach community_table in array array[
    'achievement_post_comments',
    'achievement_post_likes',
    'comment_likes',
    'profile_post_comments',
    'profile_post_likes',
    'reel_comments',
    'reel_likes',
    'saved_posts',
    'trade_comments',
    'trade_likes',
    'user_reviews'
  ]
  loop
    execute format(
      'drop policy if exists %I on public.%I',
      community_table || '_hide_from_community',
      community_table
    );
    execute format(
      'create policy %I on public.%I as restrictive for select to anon, authenticated using (public.profile_is_visible_to_viewer(user_id))',
      community_table || '_hide_from_community',
      community_table
    );
  end loop;
end
$policies$;

-- Direct profile gateway used by profile bootstrap.
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

  if not public.profile_is_visible_to_viewer(v.id) then
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
  'Profile bootstrap row. Hidden profiles, blocked peers, and missing usernames return null. Non-owners do not receive billing or locked-account columns.';

revoke all on function public.profile_reader_row(text) from public;
grant execute on function public.profile_reader_row(text) to anon, authenticated;

-- Security-definer community readers that bypass RLS.
do $mig$
declare
  src text;
  updated text;
begin
  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'leaderboard_ranked_window_one';

  updated := replace(
    src,
    'where coalesce(pr.is_private, false) = false',
    'where coalesce(pr.is_private, false) = false and public.profile_is_visible_to_viewer(pr.id)'
  );
  if position('public.profile_is_visible_to_viewer' in coalesce(src, '')) = 0 then
    if updated = src or src is null then
      raise exception 'leaderboard_ranked_window_one visibility predicate was not found';
    end if;
    execute updated;
  end if;

  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'leaderboard_trade_rows'
    and pg_get_function_identity_arguments(p.oid) = 'p_offset integer, p_limit integer';

  updated := replace(
    src,
    'where coalesce(p.is_private, false) = false',
    'where coalesce(p.is_private, false) = false and public.profile_is_visible_to_viewer(p.id)'
  );
  if position('public.profile_is_visible_to_viewer' in coalesce(src, '')) = 0 then
    if updated = src or src is null then
      raise exception 'leaderboard_trade_rows visibility predicate was not found';
    end if;
    execute updated;
  end if;

  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'leaderboard_trade_rows_page';

  updated := replace(
    src,
    'where coalesce(p.is_private, false) = false',
    'where coalesce(p.is_private, false) = false and public.profile_is_visible_to_viewer(p.id)'
  );
  if position('public.profile_is_visible_to_viewer' in coalesce(src, '')) = 0 then
    if updated = src or src is null then
      raise exception 'leaderboard_trade_rows_page visibility predicate was not found';
    end if;
    execute updated;
  end if;

  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_profile_account_insights';

  updated := replace(
    src,
    'if v_profile.id is null then',
    'if v_profile.id is null or not public.profile_is_visible_to_viewer(v_profile.id) then'
  );
  if position('public.profile_is_visible_to_viewer' in coalesce(src, '')) = 0 then
    if updated = src or src is null then
      raise exception 'rpc_v1_profile_account_insights visibility predicate was not found';
    end if;
    execute updated;
  end if;

  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'recipient_allows_dm';

  src := replace(src, E'\r', '');
  updated := replace(
    src,
    $old$if p_sender is null or p_recipient is null or p_sender = p_recipient then
    return false;
  end if;$old$,
    $new$if p_sender is null or p_recipient is null or p_sender = p_recipient then
    return false;
  end if;

  if not public.profile_is_visible_to_viewer(p_recipient) then
    return false;
  end if;$new$
  );
  if position('public.profile_is_visible_to_viewer' in coalesce(src, '')) = 0 then
    if updated = src or src is null then
      raise exception 'recipient_allows_dm visibility predicate was not found';
    end if;
    execute updated;
  end if;

  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'profile_viewer_can_view_trades';

  src := replace(src, E'\r', '');
  updated := replace(
    src,
    $old$      select (
        auth.uid() = p_profile_id
        or coalesce(p.is_private, false) = false
        or exists (
          select 1
          from public.followers f
          where f.follower_id = auth.uid()
            and f.following_id = p_profile_id
        )
      )$old$,
    $new$      select (
        public.profile_is_visible_to_viewer(p_profile_id)
        and (
          auth.uid() = p_profile_id
          or coalesce(p.is_private, false) = false
          or exists (
            select 1
            from public.followers f
            where f.follower_id = auth.uid()
              and f.following_id = p_profile_id
          )
        )
      )$new$
  );
  if position('public.profile_is_visible_to_viewer' in coalesce(src, '')) = 0 then
    if updated = src or src is null then
      raise exception 'profile_viewer_can_view_trades visibility predicate was not found';
    end if;
    execute updated;
  end if;

  -- Public room message readers bypass RLS. Hide messages whose author is hidden.
  for src in
    select pg_get_functiondef(p.oid)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('rpc_v1_room_bootstrap', 'rpc_v1_public_room_guest_bootstrap')
  loop
    src := replace(src, E'\r', '');
    updated := regexp_replace(
      src,
      'from public\.room_messages msg\s+where msg\.room_id = p_room_id',
      'from public.room_messages msg where msg.room_id = p_room_id and public.profile_is_visible_to_viewer(msg.user_id)',
      'g'
    );
    if updated = src then
      raise exception 'room message visibility predicate was not found';
    end if;
    execute updated;
  end loop;

  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_room_bootstrap_message_row';

  src := replace(src, E'\r', '');
  updated := replace(
    src,
    'where m.id = p_message_id',
    'where m.id = p_message_id and public.profile_is_visible_to_viewer(m.user_id)'
  );
  if position('public.profile_is_visible_to_viewer' in coalesce(src, '')) = 0 then
    if updated = src or src is null then
      raise exception 'rpc_v1_room_bootstrap_message_row visibility predicate was not found';
    end if;
    execute updated;
  end if;

  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_public_room_guest_message_row';

  src := replace(src, E'\r', '');
  updated := replace(
    src,
    'join public.room_messages m on m.id = p_message_id and m.room_id = p_room_id',
    'join public.room_messages m on m.id = p_message_id and m.room_id = p_room_id and public.profile_is_visible_to_viewer(m.user_id)'
  );
  if position('public.profile_is_visible_to_viewer' in coalesce(src, '')) = 0 then
    if updated = src or src is null then
      raise exception 'rpc_v1_public_room_guest_message_row visibility predicate was not found';
    end if;
    execute updated;
  end if;

  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'list_public_user_reviews';

  src := replace(src, E'\r', '');
  updated := replace(
    src,
    'where r.status = ''approved''',
    'where r.status = ''approved'' and public.profile_is_visible_to_viewer(r.user_id)'
  );
  if position('public.profile_is_visible_to_viewer' in coalesce(src, '')) = 0 then
    if updated = src or src is null then
      raise exception 'list_public_user_reviews visibility predicate was not found';
    end if;
    execute updated;
  end if;

  -- Community rooms owned by a hidden profile drop out of discovery. Official rooms stay.
  for src in
    select pg_get_functiondef(p.oid)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'popular_trade_rooms',
        'search_public_trade_rooms',
        'rpc_v1_search_trade_rooms',
        'rpc_v1_trade_room_discovery',
        'rpc_v1_trade_rooms_home_bootstrap'
      )
  loop
    src := replace(src, E'\r', '');
    updated := replace(
      src,
      'and coalesce(p.is_private, false) = false',
      'and coalesce(p.is_private, false) = false and public.profile_is_visible_to_viewer(p.id)'
    );
    if updated = src then
      raise exception 'trade room owner visibility predicate was not found';
    end if;
    execute updated;
  end loop;
end
$mig$;

-- Admin directory keeps hidden accounts. This RPC does not apply the public visibility filter.
drop function if exists public.admin_list_users(text, boolean, boolean, boolean, int, int);

create or replace function public.admin_list_users(
  p_search text default null,
  p_banned boolean default null,
  p_pro boolean default null,
  p_private boolean default null,
  p_limit int default 40,
  p_offset int default 0
)
returns table (
  id uuid,
  username text,
  name text,
  email text,
  avatar_url text,
  created_at timestamptz,
  is_private boolean,
  is_pro boolean,
  subscription_status text,
  referral_code text,
  is_banned boolean,
  banned_reason text,
  banned_at timestamptz,
  is_beta_tester boolean,
  is_hidden_from_community boolean,
  full_count bigint
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  uid uuid := auth.uid();
  lim int := greatest(1, least(coalesce(p_limit, 40), 100));
  off int := greatest(0, coalesce(p_offset, 0));
  q text := nullif(trim(coalesce(p_search, '')), '');
begin
  if uid is null or not exists (select 1 from public.admin_users au where au.user_id = uid) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  return query
  select
    p.id,
    p.username::text,
    coalesce(p.name, '')::text as name,
    coalesce(u.email, '')::text as email,
    p.avatar_url::text,
    coalesce(p.created_at, now()) as created_at,
    coalesce(p.is_private, false) as is_private,
    coalesce(p.is_pro, false) as is_pro,
    coalesce(p.subscription_status, '')::text as subscription_status,
    coalesce(p.referral_code, '')::text as referral_code,
    coalesce(p.is_banned, false) as is_banned,
    p.banned_reason::text,
    p.banned_at,
    coalesce(p.is_beta_tester, false) as is_beta_tester,
    coalesce(p.is_hidden_from_community, false) as is_hidden_from_community,
    count(*) over ()::bigint as full_count
  from public.profiles p
  left join auth.users u on u.id = p.id
  where
    (q is null or p.username ilike '%' || q || '%' or coalesce(p.name, '') ilike '%' || q || '%'
      or coalesce(u.email, '') ilike '%' || q || '%')
    and (
      p_banned is null
      or (p_banned = true and coalesce(p.is_banned, false) = true)
      or (p_banned = false and coalesce(p.is_banned, false) = false)
    )
    and (
      p_pro is null
      or (
        p_pro = true
        and (
          coalesce(p.is_pro, false) = true
          or lower(trim(coalesce(p.subscription_status, ''))) in ('active', 'trialing')
        )
      )
      or (
        p_pro = false
        and coalesce(p.is_pro, false) = false
        and lower(trim(coalesce(p.subscription_status, ''))) not in ('active', 'trialing')
      )
    )
    and (
      p_private is null
      or (p_private = true and coalesce(p.is_private, false) = true)
      or (p_private = false and coalesce(p.is_private, false) = false)
    )
  order by coalesce(p.created_at, now()) desc
  limit lim
  offset off;
end;
$$;

revoke all on function public.admin_list_users(text, boolean, boolean, boolean, int, int) from public;
grant execute on function public.admin_list_users(text, boolean, boolean, boolean, int, int) to authenticated;

comment on function public.admin_list_users(text, boolean, boolean, boolean, int, int) is
  'Admin user directory. Includes accounts hidden from the community.';
