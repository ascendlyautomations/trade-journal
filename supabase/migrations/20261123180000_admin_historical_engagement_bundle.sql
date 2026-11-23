-- Historical engagement analytics from content created_at timestamps (not product sessions).
-- Parallel to admin_product_analytics_bundle; does not modify product rollups or legacy bundle.

-- Helper for retention EXISTS checks (organic trade + social + messages on a UTC day).
create or replace function public.admin_historical_engagement_had_content_action(p_user_id uuid, p_activity_day date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.trades t
    where t.user_id = p_user_id
      and not coalesce(t.is_initial_import, false)
      and (date_trunc('day', timezone('utc', t.created_at)))::date = p_activity_day
  )
  or exists (
    select 1 from public.posts po
    where po.user_id = p_user_id
      and (date_trunc('day', timezone('utc', po.created_at)))::date = p_activity_day
  )
  or exists (
    select 1 from public.profile_posts pp
    where pp.user_id = p_user_id
      and (date_trunc('day', timezone('utc', pp.created_at)))::date = p_activity_day
  )
  or exists (
    select 1 from public.reels r
    where r.user_id = p_user_id
      and (date_trunc('day', timezone('utc', r.created_at)))::date = p_activity_day
  )
  or exists (
    select 1 from public.comments c
    where c.user_id = p_user_id
      and (date_trunc('day', timezone('utc', c.created_at)))::date = p_activity_day
  )
  or exists (
    select 1 from public.likes l
    where l.user_id = p_user_id
      and (date_trunc('day', timezone('utc', l.created_at)))::date = p_activity_day
  )
  or exists (
    select 1 from public.followers f
    where f.follower_id = p_user_id
      and (date_trunc('day', timezone('utc', f.created_at)))::date = p_activity_day
  )
  or exists (
    select 1 from public.messages m
    where m.sender_id = p_user_id
      and (date_trunc('day', timezone('utc', m.created_at)))::date = p_activity_day
  );
$$;

revoke all on function public.admin_historical_engagement_had_content_action(uuid, date) from public;

create or replace function public.admin_historical_engagement_bundle(p_series_days int default 90)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller_user_id uuid := auth.uid();
  day_start timestamptz := date_trunc('day', timezone('utc', now()));
  series_days int := greatest(1, least(p_series_days, 365));
  series_from timestamptz := day_start - (series_days - 1) * interval '1 day';
  series_from_date date := (series_from at time zone 'utc')::date;
  day_start_date date := (day_start at time zone 'utc')::date;
  week_start_date date := day_start_date - 6;
  month_start_date date := day_start_date - 29;
  v_notes text[] := array[
    'Historical engagement uses row created_at timestamps — not app sessions, opens, or product DAU.',
    'Trades by execution date (trade_date) are labeled separately; they are not app activity.',
    'Web vs iOS platform splits are unavailable before product analytics tracking.',
    'Active traders and content-action retention exclude bulk journal rows (is_initial_import = true).'
  ]::text[];
  v_engaged_dau bigint := 0;
  v_engaged_wau bigint := 0;
  v_engaged_mau bigint := 0;
  v_traders_dau bigint := 0;
  v_creators_dau bigint := 0;
  v_messengers_dau bigint := 0;
  v_signups_period bigint := 0;
  v_accounts_period bigint := 0;
  v_d1 numeric;
  v_d7 numeric;
  v_d30 numeric;
  v_cohort_all int := 0;
  v_d1_mature int := 0;
  v_d7_mature int := 0;
  v_d30_mature int := 0;
  v_retention_insufficient boolean := false;
  j_signups jsonb;
  j_accounts jsonb;
  j_trades_logged jsonb;
  j_trades_organic jsonb;
  j_trades_bulk jsonb;
  j_trades_execution jsonb;
  j_active_traders jsonb;
  j_returning_traders jsonb;
  j_posts jsonb;
  j_profile_posts jsonb;
  j_reels jsonb;
  j_comments jsonb;
  j_likes jsonb;
  j_follows jsonb;
  j_messages jsonb;
  j_active_creators jsonb;
  j_active_messengers jsonb;
  j_engaged_users jsonb;
  j_returning_engaged jsonb;
  j_returning_creators jsonb;
  j_import_quality jsonb;
begin
  if caller_user_id is null or not exists (
    select 1 from public.admin_users au where au.user_id = caller_user_id
  ) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  -- Signups per day
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
  ),
  coalesce(sum(coalesce(sc.c, 0)), 0)::bigint
  into j_signups, v_signups_period
  from day_series ds
  left join signup_counts sc on sc.day = ds.day;

  -- Trading accounts created
  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  acct_counts as (
    select (date_trunc('day', timezone('utc', coalesce(a.created_at, now()))))::date as day,
           count(*)::bigint as c
    from public.accounts a
    where coalesce(a.created_at, now()) >= series_from
    group by 1
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(ac.c, 0)) order by ds.day),
    '[]'::jsonb
  ),
  coalesce(sum(coalesce(ac.c, 0)), 0)::bigint
  into j_accounts, v_accounts_period
  from day_series ds
  left join acct_counts ac on ac.day = ds.day;

  -- Trades logged (all created_at)
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
  into j_trades_logged
  from day_series ds
  left join trade_counts tc on tc.day = ds.day;

  -- Organic trades logged (exclude bulk initial import)
  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  trade_counts as (
    select (date_trunc('day', timezone('utc', t.created_at)))::date as day,
           count(*)::bigint as c
    from public.trades t
    where t.created_at is not null
      and t.created_at >= series_from
      and not coalesce(t.is_initial_import, false)
    group by 1
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(tc.c, 0)) order by ds.day),
    '[]'::jsonb
  )
  into j_trades_organic
  from day_series ds
  left join trade_counts tc on tc.day = ds.day;

  -- Bulk import trades
  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  trade_counts as (
    select (date_trunc('day', timezone('utc', t.created_at)))::date as day,
           count(*)::bigint as c
    from public.trades t
    where t.created_at is not null
      and t.created_at >= series_from
      and coalesce(t.is_initial_import, false) = true
    group by 1
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(tc.c, 0)) order by ds.day),
    '[]'::jsonb
  )
  into j_trades_bulk
  from day_series ds
  left join trade_counts tc on tc.day = ds.day;

  -- Execution dates (trade_date) — informational, not app activity
  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  exec_counts as (
    select t.trade_date::date as day,
           count(*)::bigint as c
    from public.trades t
    where t.trade_date is not null
      and t.trade_date::date >= series_from_date
      and t.trade_date::date <= day_start_date
    group by 1
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(ec.c, 0)) order by ds.day),
    '[]'::jsonb
  )
  into j_trades_execution
  from day_series ds
  left join exec_counts ec on ec.day = ds.day;

  -- Active organic traders per day
  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  trader_counts as (
    select (date_trunc('day', timezone('utc', t.created_at)))::date as day,
           count(distinct t.user_id)::bigint as c
    from public.trades t
    where t.created_at is not null
      and t.created_at >= series_from
      and t.user_id is not null
      and not coalesce(t.is_initial_import, false)
    group by 1
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(tr.c, 0)) order by ds.day),
    '[]'::jsonb
  )
  into j_active_traders
  from day_series ds
  left join trader_counts tr on tr.day = ds.day;

  -- Returning organic traders
  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  returning_counts as (
    select (date_trunc('day', timezone('utc', t.created_at)))::date as activity_day,
           count(distinct t.user_id)::bigint as c
    from public.trades t
    where t.created_at is not null
      and t.created_at >= series_from
      and t.user_id is not null
      and not coalesce(t.is_initial_import, false)
      and exists (
        select 1
        from public.trades prior
        where prior.user_id = t.user_id
          and not coalesce(prior.is_initial_import, false)
          and prior.created_at is not null
          and (date_trunc('day', timezone('utc', prior.created_at)))::date
              < (date_trunc('day', timezone('utc', t.created_at)))::date
      )
    group by 1
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(rc.c, 0)) order by ds.day),
    '[]'::jsonb
  )
  into j_returning_traders
  from day_series ds
  left join returning_counts rc on rc.activity_day = ds.day;

  -- Social count helpers via repeated pattern for each table
  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  post_counts as (
    select (date_trunc('day', timezone('utc', po.created_at)))::date as day, count(*)::bigint as c
    from public.posts po
    where po.created_at is not null and po.created_at >= series_from
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(pc.c, 0)) order by ds.day), '[]'::jsonb)
  into j_posts
  from day_series ds left join post_counts pc on pc.day = ds.day;

  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  counts as (
    select (date_trunc('day', timezone('utc', pp.created_at)))::date as day, count(*)::bigint as c
    from public.profile_posts pp
    where pp.created_at is not null and pp.created_at >= series_from
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(c.c, 0)) order by ds.day), '[]'::jsonb)
  into j_profile_posts
  from day_series ds left join counts c on c.day = ds.day;

  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  counts as (
    select (date_trunc('day', timezone('utc', r.created_at)))::date as day, count(*)::bigint as c
    from public.reels r
    where r.created_at is not null and r.created_at >= series_from
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(c.c, 0)) order by ds.day), '[]'::jsonb)
  into j_reels
  from day_series ds left join counts c on c.day = ds.day;

  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  counts as (
    select (date_trunc('day', timezone('utc', c.created_at)))::date as day, count(*)::bigint as c
    from public.comments c
    where c.created_at is not null and c.created_at >= series_from
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(x.c, 0)) order by ds.day), '[]'::jsonb)
  into j_comments
  from day_series ds left join counts x on x.day = ds.day;

  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  counts as (
    select (date_trunc('day', timezone('utc', l.created_at)))::date as day, count(*)::bigint as c
    from public.likes l
    where l.created_at is not null and l.created_at >= series_from
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(x.c, 0)) order by ds.day), '[]'::jsonb)
  into j_likes
  from day_series ds left join counts x on x.day = ds.day;

  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  counts as (
    select (date_trunc('day', timezone('utc', f.created_at)))::date as day, count(*)::bigint as c
    from public.followers f
    where f.created_at is not null and f.created_at >= series_from
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(x.c, 0)) order by ds.day), '[]'::jsonb)
  into j_follows
  from day_series ds left join counts x on x.day = ds.day;

  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  counts as (
    select (date_trunc('day', timezone('utc', m.created_at)))::date as day, count(*)::bigint as c
    from public.messages m
    where m.created_at is not null and m.created_at >= series_from
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(x.c, 0)) order by ds.day), '[]'::jsonb)
  into j_messages
  from day_series ds left join counts x on x.day = ds.day;

  -- Active creators (posts, profile posts, reels)
  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  creator_activity as (
    select (date_trunc('day', timezone('utc', po.created_at)))::date as activity_day, po.user_id as uid
    from public.posts po
    where po.created_at is not null and po.created_at >= series_from and po.user_id is not null
    union all
    select (date_trunc('day', timezone('utc', pp.created_at)))::date, pp.user_id
    from public.profile_posts pp
    where pp.created_at is not null and pp.created_at >= series_from and pp.user_id is not null
    union all
    select (date_trunc('day', timezone('utc', r.created_at)))::date, r.user_id
    from public.reels r
    where r.created_at is not null and r.created_at >= series_from and r.user_id is not null
  ),
  by_day as (
    select ca.activity_day, count(distinct ca.uid)::bigint as c
    from creator_activity ca
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(bd.c, 0)) order by ds.day), '[]'::jsonb)
  into j_active_creators
  from day_series ds left join by_day bd on bd.activity_day = ds.day;

  -- Active messengers
  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  messenger_counts as (
    select (date_trunc('day', timezone('utc', m.created_at)))::date as day,
           count(distinct m.sender_id)::bigint as c
    from public.messages m
    where m.created_at is not null and m.created_at >= series_from and m.sender_id is not null
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(mc.c, 0)) order by ds.day), '[]'::jsonb)
  into j_active_messengers
  from day_series ds left join messenger_counts mc on mc.day = ds.day;

  -- Engaged users union
  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  activity as (
    select (date_trunc('day', timezone('utc', t.created_at)))::date as activity_day, t.user_id as uid
    from public.trades t
    where t.created_at is not null and t.created_at >= series_from and t.user_id is not null
      and not coalesce(t.is_initial_import, false)
    union all
    select (date_trunc('day', timezone('utc', po.created_at)))::date, po.user_id
    from public.posts po where po.created_at is not null and po.created_at >= series_from and po.user_id is not null
    union all
    select (date_trunc('day', timezone('utc', pp.created_at)))::date, pp.user_id
    from public.profile_posts pp where pp.created_at is not null and pp.created_at >= series_from and pp.user_id is not null
    union all
    select (date_trunc('day', timezone('utc', r.created_at)))::date, r.user_id
    from public.reels r where r.created_at is not null and r.created_at >= series_from and r.user_id is not null
    union all
    select (date_trunc('day', timezone('utc', c.created_at)))::date, c.user_id
    from public.comments c where c.created_at is not null and c.created_at >= series_from and c.user_id is not null
    union all
    select (date_trunc('day', timezone('utc', l.created_at)))::date, l.user_id
    from public.likes l where l.created_at is not null and l.created_at >= series_from and l.user_id is not null
    union all
    select (date_trunc('day', timezone('utc', f.created_at)))::date, f.follower_id
    from public.followers f where f.created_at is not null and f.created_at >= series_from and f.follower_id is not null
    union all
    select (date_trunc('day', timezone('utc', m.created_at)))::date, m.sender_id
    from public.messages m where m.created_at is not null and m.created_at >= series_from and m.sender_id is not null
  ),
  by_day as (
    select act.activity_day, count(distinct act.uid)::bigint as c
    from activity act
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(bd.c, 0)) order by ds.day), '[]'::jsonb)
  into j_engaged_users
  from day_series ds left join by_day bd on bd.activity_day = ds.day;

  -- Returning engaged users
  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  activity as (
    select (date_trunc('day', timezone('utc', t.created_at)))::date as activity_day, t.user_id as uid
    from public.trades t
    where t.created_at is not null and t.created_at >= series_from and t.user_id is not null
      and not coalesce(t.is_initial_import, false)
    union all
    select (date_trunc('day', timezone('utc', po.created_at)))::date, po.user_id
    from public.posts po where po.created_at is not null and po.created_at >= series_from
    union all
    select (date_trunc('day', timezone('utc', pp.created_at)))::date, pp.user_id
    from public.profile_posts pp where pp.created_at is not null and pp.created_at >= series_from
    union all
    select (date_trunc('day', timezone('utc', r.created_at)))::date, r.user_id
    from public.reels r where r.created_at is not null and r.created_at >= series_from
    union all
    select (date_trunc('day', timezone('utc', c.created_at)))::date, c.user_id
    from public.comments c where c.created_at is not null and c.created_at >= series_from
    union all
    select (date_trunc('day', timezone('utc', l.created_at)))::date, l.user_id
    from public.likes l where l.created_at is not null and l.created_at >= series_from
    union all
    select (date_trunc('day', timezone('utc', f.created_at)))::date, f.follower_id
    from public.followers f where f.created_at is not null and f.created_at >= series_from
    union all
    select (date_trunc('day', timezone('utc', m.created_at)))::date, m.sender_id
    from public.messages m where m.created_at is not null and m.created_at >= series_from
  ),
  returning_counts as (
    select act.activity_day, count(distinct act.uid)::bigint as c
    from activity act
    where exists (
      select 1
      from activity prior
      where prior.uid = act.uid and prior.activity_day < act.activity_day
    )
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(rc.c, 0)) order by ds.day), '[]'::jsonb)
  into j_returning_engaged
  from day_series ds left join returning_counts rc on rc.activity_day = ds.day;

  -- Returning creators
  with day_series as (
    select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
  ),
  creator_activity as (
    select (date_trunc('day', timezone('utc', po.created_at)))::date as activity_day, po.user_id as uid
    from public.posts po where po.created_at is not null and po.created_at >= series_from and po.user_id is not null
    union all
    select (date_trunc('day', timezone('utc', pp.created_at)))::date, pp.user_id
    from public.profile_posts pp where pp.created_at is not null and pp.created_at >= series_from and pp.user_id is not null
    union all
    select (date_trunc('day', timezone('utc', r.created_at)))::date, r.user_id
    from public.reels r where r.created_at is not null and r.created_at >= series_from and r.user_id is not null
  ),
  returning_counts as (
    select ca.activity_day, count(distinct ca.uid)::bigint as c
    from creator_activity ca
    where exists (
      select 1 from creator_activity prior
      where prior.uid = ca.uid and prior.activity_day < ca.activity_day
    )
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(rc.c, 0)) order by ds.day), '[]'::jsonb)
  into j_returning_creators
  from day_series ds left join returning_counts rc on rc.activity_day = ds.day;

  -- Overview DAU / WAU / MAU from engaged union
  with activity as (
    select (date_trunc('day', timezone('utc', t.created_at)))::date as activity_day, t.user_id as uid
    from public.trades t
    where t.created_at is not null and t.user_id is not null and not coalesce(t.is_initial_import, false)
    union all
    select (date_trunc('day', timezone('utc', po.created_at)))::date, po.user_id
    from public.posts po where po.created_at is not null and po.user_id is not null
    union all
    select (date_trunc('day', timezone('utc', pp.created_at)))::date, pp.user_id
    from public.profile_posts pp where pp.created_at is not null and pp.user_id is not null
    union all
    select (date_trunc('day', timezone('utc', r.created_at)))::date, r.user_id
    from public.reels r where r.created_at is not null and r.user_id is not null
    union all
    select (date_trunc('day', timezone('utc', c.created_at)))::date, c.user_id
    from public.comments c where c.created_at is not null and c.user_id is not null
    union all
    select (date_trunc('day', timezone('utc', l.created_at)))::date, l.user_id
    from public.likes l where l.created_at is not null and l.user_id is not null
    union all
    select (date_trunc('day', timezone('utc', f.created_at)))::date, f.follower_id
    from public.followers f where f.created_at is not null and f.follower_id is not null
    union all
    select (date_trunc('day', timezone('utc', m.created_at)))::date, m.sender_id
    from public.messages m where m.created_at is not null and m.sender_id is not null
  )
  select
    count(distinct uid) filter (where activity_day = day_start_date),
    count(distinct uid) filter (where activity_day >= week_start_date and activity_day <= day_start_date),
    count(distinct uid) filter (where activity_day >= month_start_date and activity_day <= day_start_date)
  into v_engaged_dau, v_engaged_wau, v_engaged_mau
  from activity;

  select count(distinct t.user_id) into v_traders_dau
  from public.trades t
  where t.created_at is not null
    and not coalesce(t.is_initial_import, false)
    and (date_trunc('day', timezone('utc', t.created_at)))::date = day_start_date;

  with creator_activity as (
    select po.user_id as uid, (date_trunc('day', timezone('utc', po.created_at)))::date as activity_day
    from public.posts po where po.created_at is not null and po.user_id is not null
    union all
    select pp.user_id, (date_trunc('day', timezone('utc', pp.created_at)))::date
    from public.profile_posts pp where pp.created_at is not null and pp.user_id is not null
    union all
    select r.user_id, (date_trunc('day', timezone('utc', r.created_at)))::date
    from public.reels r where r.created_at is not null and r.user_id is not null
  )
  select count(distinct uid) into v_creators_dau
  from creator_activity
  where activity_day = day_start_date;

  select count(distinct m.sender_id) into v_messengers_dau
  from public.messages m
  where m.created_at is not null and m.sender_id is not null
    and (date_trunc('day', timezone('utc', m.created_at)))::date = day_start_date;

  -- Import quality in period
  select jsonb_build_object(
    'manualEntered', coalesce(sum(case when trade_bucket = 'manual_entered' then c else 0 end), 0),
    'unsetImportSource', coalesce(sum(case when trade_bucket = 'unset_source' then c else 0 end), 0),
    'csv', coalesce(sum(case when trade_bucket = 'csv' then c else 0 end), 0),
    'broker', coalesce(sum(case when trade_bucket = 'broker' then c else 0 end), 0),
    'other', coalesce(sum(case when trade_bucket = 'other' then c else 0 end), 0),
    'bulkInitialImportRows', (
      select count(*)::bigint from public.trades t
      where t.created_at >= series_from and coalesce(t.is_initial_import, false) = true
    ),
    'organicTradesLogged', (
      select count(*)::bigint from public.trades t
      where t.created_at >= series_from and not coalesce(t.is_initial_import, false)
    ),
    'tradeDateBeforeCreatedDayRows', (
      select count(*)::bigint from public.trades t
      where t.created_at >= series_from
        and t.trade_date is not null
        and t.created_at is not null
        and t.trade_date::date < (date_trunc('day', timezone('utc', t.created_at)))::date
    ),
    'nullTradeDateRows', (
      select count(*)::bigint from public.trades t
      where t.created_at >= series_from and t.trade_date is null
    )
  )
  into j_import_quality
  from (
    select
      case
        when lower(coalesce(trim(t.import_source), '')) in ('tradovate', 'rithmic') then 'broker'
        when lower(coalesce(trim(t.import_source), '')) = 'csv' then 'csv'
        when lower(coalesce(trim(t.import_source), '')) = 'manual' then 'manual_entered'
        when lower(coalesce(trim(t.import_source), '')) = '' then 'unset_source'
        else 'other'
      end as trade_bucket,
      count(*)::bigint as c
    from public.trades t
    where t.created_at >= series_from
    group by 1
  ) buckets;

  -- Content-action retention (signup cohort; organic + social)
  with cohorts as (
    select p.id as user_id,
           (date_trunc('day', timezone('utc', coalesce(p.created_at, now()))))::date as signup_day
    from public.profiles p
    where (date_trunc('day', timezone('utc', coalesce(p.created_at, now()))))::date <= day_start_date - 1
  ),
  scored as (
    select c.user_id,
           c.signup_day,
           (day_start_date - c.signup_day) as age_days,
           public.admin_historical_engagement_had_content_action(c.user_id, c.signup_day + 1) as d1,
           public.admin_historical_engagement_had_content_action(c.user_id, c.signup_day + 7) as d7,
           public.admin_historical_engagement_had_content_action(c.user_id, c.signup_day + 30) as d30
    from cohorts c
  )
  select count(*)::int,
         count(*) filter (where age_days >= 1)::int,
         count(*) filter (where age_days >= 7)::int,
         count(*) filter (where age_days >= 30)::int,
         case when count(*) filter (where age_days >= 1) > 0
           then round(100.0 * count(*) filter (where d1 and age_days >= 1)
                      / count(*) filter (where age_days >= 1), 2) end,
         case when count(*) filter (where age_days >= 7) > 0
           then round(100.0 * count(*) filter (where d7 and age_days >= 7)
                      / count(*) filter (where age_days >= 7), 2) end,
         case when count(*) filter (where age_days >= 30) > 0
           then round(100.0 * count(*) filter (where d30 and age_days >= 30)
                      / count(*) filter (where age_days >= 30), 2) end
  into v_cohort_all, v_d1_mature, v_d7_mature, v_d30_mature, v_d1, v_d7, v_d30
  from scored;

  v_retention_insufficient := coalesce(v_d1_mature, 0) = 0
    and coalesce(v_d7_mature, 0) = 0
    and coalesce(v_d30_mature, 0) = 0;

  return jsonb_build_object(
    'seriesDays', series_days,
    'meta', jsonb_build_object(
      'notes', to_jsonb(v_notes),
      'isContentActivityNotSessions', true,
      'maxSeriesDays', 365
    ),
    'overview', jsonb_build_object(
      'engagedDau', coalesce(v_engaged_dau, 0),
      'engagedWau', coalesce(v_engaged_wau, 0),
      'engagedMau', coalesce(v_engaged_mau, 0),
      'activeTradersDau', coalesce(v_traders_dau, 0),
      'activeCreatorsDau', coalesce(v_creators_dau, 0),
      'activeMessengersDau', coalesce(v_messengers_dau, 0),
      'newSignupsInPeriod', coalesce(v_signups_period, 0),
      'accountsCreatedInPeriod', coalesce(v_accounts_period, 0)
    ),
    'growth', jsonb_build_object(
      'signupsPerDay', coalesce(j_signups, '[]'::jsonb),
      'accountsCreatedPerDay', coalesce(j_accounts, '[]'::jsonb)
    ),
    'trading', jsonb_build_object(
      'tradesLoggedPerDay', coalesce(j_trades_logged, '[]'::jsonb),
      'organicTradesLoggedPerDay', coalesce(j_trades_organic, '[]'::jsonb),
      'bulkImportTradesPerDay', coalesce(j_trades_bulk, '[]'::jsonb),
      'tradesByExecutionDatePerDay', coalesce(j_trades_execution, '[]'::jsonb),
      'activeTradersPerDay', coalesce(j_active_traders, '[]'::jsonb),
      'returningTradersPerDay', coalesce(j_returning_traders, '[]'::jsonb),
      'importQuality', coalesce(j_import_quality, '{}'::jsonb)
    ),
    'social', jsonb_build_object(
      'postsPerDay', coalesce(j_posts, '[]'::jsonb),
      'profilePostsPerDay', coalesce(j_profile_posts, '[]'::jsonb),
      'reelsPerDay', coalesce(j_reels, '[]'::jsonb),
      'commentsPerDay', coalesce(j_comments, '[]'::jsonb),
      'likesPerDay', coalesce(j_likes, '[]'::jsonb),
      'followsPerDay', coalesce(j_follows, '[]'::jsonb),
      'messagesPerDay', coalesce(j_messages, '[]'::jsonb),
      'activeCreatorsPerDay', coalesce(j_active_creators, '[]'::jsonb),
      'activeMessengersPerDay', coalesce(j_active_messengers, '[]'::jsonb)
    ),
    'engagement', jsonb_build_object(
      'engagedUsersPerDay', coalesce(j_engaged_users, '[]'::jsonb),
      'returningEngagedUsersPerDay', coalesce(j_returning_engaged, '[]'::jsonb),
      'returningCreatorsPerDay', coalesce(j_returning_creators, '[]'::jsonb)
    ),
    'retention', jsonb_build_object(
      'd1Rate', v_d1,
      'd7Rate', v_d7,
      'd30Rate', v_d30,
      'cohortSignupsTotal', coalesce(v_cohort_all, 0),
      'd1MatureCohortSize', coalesce(v_d1_mature, 0),
      'd7MatureCohortSize', coalesce(v_d7_mature, 0),
      'd30MatureCohortSize', coalesce(v_d30_mature, 0),
      'insufficientData', v_retention_insufficient,
      'definition', 'Share of signups with organic trade or social/message content action on calendar day D+1, D+7, D+30 (UTC).'
    )
  );
end;
$$;

revoke all on function public.admin_historical_engagement_bundle(int) from public;
grant execute on function public.admin_historical_engagement_bundle(int) to authenticated;