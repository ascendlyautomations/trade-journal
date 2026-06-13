-- Repair duplicate admin RPCs after out-of-order application of 20260417210000 vs 20260417220000.
-- 1) Drop obsolete text-filter admin_list_users overload (keeps boolean-filter version).
-- 2) Restore camelCase admin_analytics_bundle expected by lib/adminAnalytics.ts.
-- Does NOT touch admin_recent_audit, bug_reports, support, feedback, affiliates, auth, or profiles schema.

drop function if exists public.admin_list_users(text, text, text, text, int, int);

-- ---------------------------------------------------------------------------
-- admin_analytics_bundle: camelCase metrics + nested series (UTC)
-- From 20260417220000_admin_list_users_boolean_filters_analytics_camelcase.sql
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
