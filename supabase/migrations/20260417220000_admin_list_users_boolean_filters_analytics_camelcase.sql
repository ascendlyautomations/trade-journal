-- Align admin_list_users filters with boolean | null (null = no filter).
-- Align admin_analytics_bundle JSON with camelCase + nested series (matches app + PostgREST clients).

drop function if exists public.admin_list_users(text, text, text, text, int, int);

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
  full_count bigint
)
language plpgsql
stable
security definer
set search_path = public, auth
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

-- ---------------------------------------------------------------------------
-- admin_analytics_bundle: camelCase metrics + nested series (UTC)
-- ---------------------------------------------------------------------------
drop function if exists public.admin_analytics_bundle(int);

create or replace function public.admin_analytics_bundle(p_series_days int default 14)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  day_start timestamptz := date_trunc('day', timezone('utc', now()));
  week_start timestamptz := day_start - interval '6 days';
  day24 timestamptz := timezone('utc', now()) - interval '24 hours';
  week7 timestamptz := timezone('utc', now()) - interval '7 days';
  series_from timestamptz := day_start - (greatest(1, least(p_series_days, 90))::int - 1) * interval '1 day';
  series_users jsonb;
  series_trades_arr jsonb;
  series_posts_arr jsonb;
begin
  if uid is null or not exists (select 1 from public.admin_users au where au.user_id = uid) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  select coalesce(
    (select jsonb_agg(jsonb_build_object('day', d::text, 'count', c) order by d)
     from (
       select date_trunc('day', timezone('utc', coalesce(p.created_at, now())))::date as d,
              count(*)::bigint as c
       from public.profiles p
       where coalesce(p.created_at, now()) >= series_from
       group by 1
     ) s),
    '[]'::jsonb
  )
  into series_users;

  select coalesce(
    (select jsonb_agg(jsonb_build_object('day', d::text, 'count', c) order by d)
     from (
       select date_trunc('day', timezone('utc', t.created_at))::date as d,
              count(*)::bigint as c
       from public.trades t
       where t.created_at is not null and t.created_at >= series_from
       group by 1
     ) st),
    '[]'::jsonb
  )
  into series_trades_arr;

  select coalesce(
    (select jsonb_agg(jsonb_build_object('day', d::text, 'count', c) order by d)
     from (
       select date_trunc('day', timezone('utc', po.created_at))::date as d,
              count(*)::bigint as c
       from public.posts po
       where po.created_at is not null and po.created_at >= series_from
       group by 1
     ) sp),
    '[]'::jsonb
  )
  into series_posts_arr;

  return jsonb_build_object(
    'totalUsers', (select count(*)::bigint from public.profiles),
    'newUsersToday', (
      select count(*)::bigint from public.profiles p
      where coalesce(p.created_at, now()) >= day_start
    ),
    'newUsersWeek', (
      select count(*)::bigint from public.profiles p
      where coalesce(p.created_at, now()) >= week_start
    ),
    'dailyActiveUsers', (
      select count(*)::bigint from (
        select distinct t.user_id from public.trades t where t.created_at >= day24
        union
        select distinct po.user_id from public.posts po where po.created_at >= day24
        union
        select distinct pp.user_id from public.profile_posts pp where pp.created_at >= day24
        union
        select distinct s.user_id from public.stories s where s.created_at >= day24
        union
        select distinct f.user_id from public.feedback_submissions f where f.created_at >= day24
        union
        select distinct st.user_id from public.support_tickets st where st.created_at >= day24
      ) x
    ),
    'weeklyActiveUsers', (
      select count(*)::bigint from (
        select distinct t.user_id from public.trades t where t.created_at >= week7
        union
        select distinct po.user_id from public.posts po where po.created_at >= week7
        union
        select distinct pp.user_id from public.profile_posts pp where pp.created_at >= week7
        union
        select distinct s.user_id from public.stories s where s.created_at >= week7
        union
        select distinct f.user_id from public.feedback_submissions f where f.created_at >= week7
        union
        select distinct st.user_id from public.support_tickets st where st.created_at >= week7
      ) y
    ),
    'tradesToday', (
      select count(*)::bigint from public.trades t where t.created_at >= day_start
    ),
    'tradesWeek', (
      select count(*)::bigint from public.trades t where t.created_at >= week_start
    ),
    'postsToday', (
      select count(*)::bigint from public.posts p where p.created_at >= day_start
    ),
    'postsWeek', (
      select count(*)::bigint from public.posts p where p.created_at >= week_start
    ),
    'totalTrades', (select count(*)::bigint from public.trades),
    'totalPosts', (select count(*)::bigint from public.posts),
    'totalFeedback', (select count(*)::bigint from public.feedback_submissions),
    'totalSupport', (select count(*)::bigint from public.support_tickets),
    'openSupport', (
      select count(*)::bigint from public.support_tickets s
      where lower(trim(coalesce(s.status, 'open'))) = 'open'
    ),
    'openFeedback', (
      select count(*)::bigint from public.feedback_submissions f
      where lower(trim(coalesce(f.status, 'open'))) = 'open'
    ),
    'bannedUsers', (
      select count(*)::bigint from public.profiles p where coalesce(p.is_banned, false) = true
    ),
    'seriesDays', greatest(1, least(p_series_days, 90)),
    'series', jsonb_build_object(
      'usersPerDay', series_users,
      'tradesPerDay', series_trades_arr,
      'postsPerDay', series_posts_arr
    )
  );
end;
$$;

revoke all on function public.admin_analytics_bundle(int) from public;
grant execute on function public.admin_analytics_bundle(int) to authenticated;
