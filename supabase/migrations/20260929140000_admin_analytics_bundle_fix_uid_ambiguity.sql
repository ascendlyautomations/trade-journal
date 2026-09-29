-- Fix PL/pgSQL `uid` variable colliding with activity CTE column `uid` (Postgres 42702).
-- Replaces admin_analytics_bundle in production after 20260929130000.

drop function if exists public.admin_analytics_bundle(int);

create or replace function public.admin_analytics_bundle(p_series_days int default 14)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller_user_id uuid := auth.uid();
  day_start timestamptz := date_trunc('day', timezone('utc', now()));
  week_start timestamptz := day_start - interval '6 days';
  day24 timestamptz := timezone('utc', now()) - interval '24 hours';
  week7 timestamptz := timezone('utc', now()) - interval '7 days';
  series_days int := greatest(1, least(p_series_days, 365));
  series_from timestamptz := day_start - (series_days - 1) * interval '1 day';
  series_from_date date := (series_from at time zone 'utc')::date;
  day_start_date date := (day_start at time zone 'utc')::date;
  series_users jsonb;
  series_trades_arr jsonb;
  series_posts_arr jsonb;
  series_active_users jsonb;
  series_reels jsonb;
  series_comments jsonb;
  series_likes jsonb;
  series_follows jsonb;
begin
  if caller_user_id is null or not exists (
    select 1 from public.admin_users au where au.user_id = caller_user_id
  ) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  signup_counts as (
    select (date_trunc('day', timezone('utc', coalesce(p.created_at, now()))))::date as day,
           count(*)::bigint as c
    from public.profiles p
    where coalesce(p.created_at, now()) >= series_from
    group by 1
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(sc.c, 0)) order by ds.day),
    '[]'::jsonb
  )
  into series_users
  from day_series ds
  left join signup_counts sc on sc.day = ds.day;

  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  trade_counts as (
    select (date_trunc('day', timezone('utc', t.created_at)))::date as day,
           count(*)::bigint as c
    from public.trades t
    where t.created_at is not null and t.created_at >= series_from
    group by 1
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(tc.c, 0)) order by ds.day),
    '[]'::jsonb
  )
  into series_trades_arr
  from day_series ds
  left join trade_counts tc on tc.day = ds.day;

  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  post_counts as (
    select (date_trunc('day', timezone('utc', po.created_at)))::date as day,
           count(*)::bigint as c
    from public.posts po
    where po.created_at is not null and po.created_at >= series_from
    group by 1
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(pc.c, 0)) order by ds.day),
    '[]'::jsonb
  )
  into series_posts_arr
  from day_series ds
  left join post_counts pc on pc.day = ds.day;

  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  activity as (
    select
      (date_trunc('day', timezone('utc', t.created_at)))::date as activity_day,
      t.user_id as active_user_id
    from public.trades t
    where t.created_at >= series_from
    union all
    select
      (date_trunc('day', timezone('utc', po.created_at)))::date,
      po.user_id
    from public.posts po
    where po.created_at >= series_from
    union all
    select
      (date_trunc('day', timezone('utc', pp.created_at)))::date,
      pp.user_id
    from public.profile_posts pp
    where pp.created_at >= series_from
    union all
    select
      (date_trunc('day', timezone('utc', s.created_at)))::date,
      s.user_id
    from public.stories s
    where s.created_at >= series_from
    union all
    select
      (date_trunc('day', timezone('utc', fb.created_at)))::date,
      fb.user_id
    from public.feedback_submissions fb
    where fb.created_at >= series_from
    union all
    select
      (date_trunc('day', timezone('utc', st.created_at)))::date,
      st.user_id
    from public.support_tickets st
    where st.created_at >= series_from
  ),
  active_by_day as (
    select
      act.activity_day,
      count(distinct act.active_user_id)::bigint as c
    from activity act
    group by act.activity_day
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(ab.c, 0)) order by ds.day),
    '[]'::jsonb
  )
  into series_active_users
  from day_series ds
  left join active_by_day ab on ab.activity_day = ds.day;

  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  reel_counts as (
    select (date_trunc('day', timezone('utc', r.created_at)))::date as day,
           count(*)::bigint as c
    from public.reels r
    where r.created_at is not null and r.created_at >= series_from
    group by 1
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(rc.c, 0)) order by ds.day),
    '[]'::jsonb
  )
  into series_reels
  from day_series ds
  left join reel_counts rc on rc.day = ds.day;

  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  comment_counts as (
    select (date_trunc('day', timezone('utc', c.created_at)))::date as day,
           count(*)::bigint as c
    from public.comments c
    where c.created_at is not null and c.created_at >= series_from
    group by 1
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(cc.c, 0)) order by ds.day),
    '[]'::jsonb
  )
  into series_comments
  from day_series ds
  left join comment_counts cc on cc.day = ds.day;

  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  like_counts as (
    select (date_trunc('day', timezone('utc', l.created_at)))::date as day,
           count(*)::bigint as c
    from public.likes l
    where l.created_at is not null and l.created_at >= series_from
    group by 1
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(lc.c, 0)) order by ds.day),
    '[]'::jsonb
  )
  into series_likes
  from day_series ds
  left join like_counts lc on lc.day = ds.day;

  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', 0) order by ds.day),
    '[]'::jsonb
  )
  into series_follows
  from day_series ds;

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
    'seriesDays', series_days,
    'series', jsonb_build_object(
      'usersPerDay', series_users,
      'tradesPerDay', series_trades_arr,
      'postsPerDay', series_posts_arr,
      'activeUsersPerDay', series_active_users,
      'reelsPerDay', series_reels,
      'commentsPerDay', series_comments,
      'likesPerDay', series_likes,
      'followsPerDay', series_follows
    )
  );
end;
$$;

revoke all on function public.admin_analytics_bundle(int) from public;
grant execute on function public.admin_analytics_bundle(int) to authenticated;
