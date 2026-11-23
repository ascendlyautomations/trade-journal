-- Phase 2 — Admin product analytics dashboard (rollups + preview funnel).
-- Does not alter admin_analytics_bundle; adds parallel RPC for product-tracked metrics.

drop function if exists public.admin_product_analytics_bundle(int);

create or replace function public.admin_product_analytics_bundle(p_series_days int default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller_user_id uuid := auth.uid();
  day_start timestamptz := date_trunc('day', timezone('utc', now()));
  series_days int := greatest(1, least(p_series_days, 90));
  series_from timestamptz := day_start - (series_days - 1) * interval '1 day';
  series_from_date date := (series_from at time zone 'utc')::date;
  day_start_date date := (day_start at time zone 'utc')::date;
  v_tracking_start date;
  v_engagement_available boolean := false;
  v_retention_available boolean := false;
  v_preview_available boolean := false;
  v_product_dau bigint;
  v_product_wau bigint;
  v_product_mau bigint;
  v_dau_mau numeric;
  v_total_users bigint;
  v_new_today bigint;
  v_d1 numeric;
  v_d7 numeric;
  v_d30 numeric;
  v_cohort_sample int := 0;
  v_trades_per_trader numeric;
  v_notes text[] := array[]::text[];
  j_signups jsonb;
  j_product_dau jsonb;
  j_returning jsonb;
  j_trades jsonb;
  j_traders jsonb;
  j_posts jsonb;
  j_profile_views jsonb;
  j_unique_viewers jsonb;
  j_feature_engagement jsonb;
  j_preview_starts jsonb;
  j_preview_exits jsonb;
  j_preview_upgrades jsonb;
  j_top_features jsonb;
  j_import_totals jsonb;
  v_preview_starts int := 0;
  v_preview_exits int := 0;
  v_preview_upgrades int := 0;
  v_preview_rate numeric;
begin
  if caller_user_id is null or not exists (
    select 1 from public.admin_users au where au.user_id = caller_user_id
  ) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  if to_regclass('public.product_daily_user_activity') is null then
    v_notes := array_append(v_notes, 'Product analytics rollups are not deployed (missing product_daily_user_activity).');
  else
    select min(pdua.activity_day) into v_tracking_start
    from public.product_daily_user_activity pdua
    where pdua.engaged = true;

    v_engagement_available := v_tracking_start is not null;
    if v_engagement_available then
      v_notes := array_append(
        v_notes,
        'Product engagement (DAU/WAU/MAU, retention) is tracked from app sessions/opens starting '
          || v_tracking_start::text || ' UTC.'
      );
    else
      v_notes := array_append(v_notes, 'No product engagement rollups yet; DAU/WAU/MAU and retention are unavailable.');
    end if;
  end if;

  select count(*)::bigint into v_total_users from public.profiles;

  select count(*)::bigint into v_new_today
  from public.profiles p
  where (date_trunc('day', timezone('utc', coalesce(p.created_at, now()))))::date = day_start_date;

  -- Growth: signups per day
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
  into j_signups
  from day_series ds
  left join signup_counts sc on sc.day = ds.day;

  if v_engagement_available then
    with day_series as (
      select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
    ),
    dau as (
      select pdua.activity_day as day, count(distinct pdua.user_id)::bigint as c
      from public.product_daily_user_activity pdua
      where pdua.engaged
        and pdua.activity_day >= series_from_date
        and pdua.activity_day <= day_start_date
      group by 1
    )
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'day', ds.day::text,
          'count', case when ds.day < v_tracking_start then null else coalesce(d.c, 0) end
        )
        order by ds.day
      ),
      '[]'::jsonb
    )
    into j_product_dau
    from day_series ds
    left join dau d on d.day = ds.day;

    select count(distinct pdua.user_id)::bigint into v_product_dau
    from public.product_daily_user_activity pdua
    where pdua.engaged and pdua.activity_day = day_start_date;

    select count(distinct pdua.user_id)::bigint into v_product_wau
    from public.product_daily_user_activity pdua
    where pdua.engaged
      and pdua.activity_day >= day_start_date - 6;

    select count(distinct pdua.user_id)::bigint into v_product_mau
    from public.product_daily_user_activity pdua
    where pdua.engaged
      and pdua.activity_day >= day_start_date - 29;

    if coalesce(v_product_mau, 0) > 0 then
      v_dau_mau := round((v_product_dau::numeric / v_product_mau::numeric), 4);
    end if;

    -- Returning users: engaged today and on a prior engaged day
    with day_series as (
      select generate_series(
        greatest(series_from_date, v_tracking_start),
        day_start_date,
        interval '1 day'
      )::date as day
    ),
    returning_counts as (
      select pdua.activity_day as day,
             count(distinct pdua.user_id)::bigint as c
      from public.product_daily_user_activity pdua
      where pdua.engaged
        and pdua.activity_day >= greatest(series_from_date, v_tracking_start)
        and exists (
          select 1
          from public.product_daily_user_activity prior
          where prior.user_id = pdua.user_id
            and prior.engaged
            and prior.activity_day < pdua.activity_day
        )
      group by 1
    )
    select coalesce(
      jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(rc.c, 0)) order by ds.day),
      '[]'::jsonb
    )
    into j_returning
    from day_series ds
    left join returning_counts rc on rc.day = ds.day;

    -- Signup cohort retention (engaged on D+1 / D+7 / D+30)
    with cohorts as (
      select p.id as user_id,
             (date_trunc('day', timezone('utc', coalesce(p.created_at, now()))))::date as signup_day
      from public.profiles p
      where (date_trunc('day', timezone('utc', coalesce(p.created_at, now()))))::date
            >= greatest(v_tracking_start, day_start_date - 60)
        and (date_trunc('day', timezone('utc', coalesce(p.created_at, now()))))::date
            <= day_start_date - 1
    ),
    scored as (
      select c.user_id,
             c.signup_day,
             exists (
               select 1 from public.product_daily_user_activity e
               where e.user_id = c.user_id and e.engaged and e.activity_day = c.signup_day + 1
             ) as d1,
             exists (
               select 1 from public.product_daily_user_activity e
               where e.user_id = c.user_id and e.engaged and e.activity_day = c.signup_day + 7
             ) as d7,
             exists (
               select 1 from public.product_daily_user_activity e
               where e.user_id = c.user_id and e.engaged and e.activity_day = c.signup_day + 30
             ) as d30,
             (day_start_date - c.signup_day) as age_days
      from cohorts c
    )
    select count(*)::int,
           case when count(*) filter (where age_days >= 1) > 0
             then round(100.0 * count(*) filter (where d1 and age_days >= 1)
                        / count(*) filter (where age_days >= 1), 2) end,
           case when count(*) filter (where age_days >= 7) > 0
             then round(100.0 * count(*) filter (where d7 and age_days >= 7)
                        / count(*) filter (where age_days >= 7), 2) end,
           case when count(*) filter (where age_days >= 30) > 0
             then round(100.0 * count(*) filter (where d30 and age_days >= 30)
                        / count(*) filter (where age_days >= 30), 2) end
    into v_cohort_sample, v_d1, v_d7, v_d30
    from scored;

    v_retention_available := v_cohort_sample > 0;
    if not v_retention_available then
      v_notes := array_append(v_notes, 'Retention cohorts need more signup history after product tracking started.');
    end if;
  else
    j_product_dau := '[]'::jsonb;
    j_returning := '[]'::jsonb;
  end if;

  -- Trading activity (exclude broker bulk initial from active-trader counts)
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
  into j_trades
  from day_series ds
  left join trade_counts tc on tc.day = ds.day;

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
      and not (
        coalesce(t.is_initial_import, false) = true
        and lower(coalesce(trim(t.import_source), '')) in ('tradovate', 'rithmic')
      )
    group by 1
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(tr.c, 0)) order by ds.day),
    '[]'::jsonb
  )
  into j_traders
  from day_series ds
  left join trader_counts tr on tr.day = ds.day;

  with latest as (
    select count(distinct t.user_id)::numeric as traders,
           count(*)::numeric as trades
    from public.trades t
    where t.created_at is not null
      and (date_trunc('day', timezone('utc', t.created_at)))::date = day_start_date
      and t.user_id is not null
      and not (
        coalesce(t.is_initial_import, false) = true
        and lower(coalesce(trim(t.import_source), '')) in ('tradovate', 'rithmic')
      )
  )
  select case when traders > 0 then round(trades / traders, 2) end
  into v_trades_per_trader
  from latest;

  select jsonb_build_object(
    'manual', coalesce(sum(case when trade_bucket = 'manual' then c else 0 end), 0),
    'csv', coalesce(sum(case when trade_bucket = 'csv' then c else 0 end), 0),
    'broker', coalesce(sum(case when trade_bucket = 'broker' then c else 0 end), 0),
    'other', coalesce(sum(case when trade_bucket = 'other' then c else 0 end), 0)
  )
  into j_import_totals
  from (
    select
      case
        when lower(coalesce(trim(t.import_source), '')) in ('tradovate', 'rithmic') then 'broker'
        when lower(coalesce(trim(t.import_source), '')) = 'csv' then 'csv'
        when lower(coalesce(trim(t.import_source), '')) in ('', 'manual') then 'manual'
        else 'other'
      end as trade_bucket,
      count(*)::bigint as c
    from public.trades t
    where t.created_at >= series_from
    group by 1
  ) x;

  -- Social
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
  into j_posts
  from day_series ds
  left join post_counts pc on pc.day = ds.day;

  if to_regclass('public.product_daily_profile_views') is not null then
    with day_series as (
      select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
    ),
    views as (
      select pv.activity_day as day,
             sum(pv.view_count)::bigint as views,
             sum(pv.unique_viewer_count)::bigint as uniques
      from public.product_daily_profile_views pv
      where pv.activity_day >= series_from_date
      group by 1
    )
    select coalesce(
      jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(v.views, 0)) order by ds.day),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(v.uniques, 0)) order by ds.day),
      '[]'::jsonb
    )
    into j_profile_views, j_unique_viewers
    from day_series ds
    left join views v on v.day = ds.day;
  else
    j_profile_views := '[]'::jsonb;
    j_unique_viewers := '[]'::jsonb;
    v_notes := array_append(v_notes, 'Profile view rollups unavailable until product analytics phase 1 is deployed.');
  end if;

  if to_regclass('public.product_daily_feature_usage') is not null then
    with day_series as (
      select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
    ),
    usage as (
      select fu.activity_day as day, sum(fu.use_count)::bigint as c
      from public.product_daily_feature_usage fu
      where fu.activity_day >= series_from_date
      group by 1
    )
    select coalesce(
      jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(u.c, 0)) order by ds.day),
      '[]'::jsonb
    )
    into j_feature_engagement
    from day_series ds
    left join usage u on u.day = ds.day;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'feature', f.feature_key,
          'uniqueUsers', f.uu,
          'webUniqueUsers', f.web_uu,
          'iosUniqueUsers', f.ios_uu,
          'useCount', f.uc
        )
        order by f.uc desc
      ),
      '[]'::jsonb
    )
    into j_top_features
    from (
      select
        fu.feature_key,
        coalesce(sum(fu.unique_users), 0)::bigint as uu,
        coalesce(sum(fu.unique_users) filter (where fu.platform = 'web'), 0)::bigint as web_uu,
        coalesce(sum(fu.unique_users) filter (where fu.platform = 'ios'), 0)::bigint as ios_uu,
        coalesce(sum(fu.use_count), 0)::bigint as uc
      from public.product_daily_feature_usage fu
      where fu.activity_day >= series_from_date
      group by fu.feature_key
      order by uc desc
      limit 15
    ) f;
  else
    j_feature_engagement := '[]'::jsonb;
    j_top_features := '[]'::jsonb;
  end if;

  if to_regclass('public.product_events') is not null then
    v_preview_available := true;
    with day_series as (
      select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
    ),
    agg as (
      select (date_trunc('day', timezone('utc', pe.occurred_at)))::date as day,
             pe.event_name,
             count(*)::int as c
      from public.product_events pe
      where pe.occurred_at >= series_from
        and pe.event_name in (
          'traxspro_preview_started',
          'traxspro_preview_exited',
          'traxspro_preview_upgrade_tapped'
        )
      group by 1, 2
    )
    select
      coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(a.c, 0)) order by ds.day) filter (where true), '[]'::jsonb)
    into j_preview_starts
    from day_series ds
    left join agg a on a.day = ds.day and a.event_name = 'traxspro_preview_started';

    with day_series as (
      select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
    ),
    agg as (
      select (date_trunc('day', timezone('utc', pe.occurred_at)))::date as day,
             pe.event_name,
             count(*)::int as c
      from public.product_events pe
      where pe.occurred_at >= series_from
        and pe.event_name = 'traxspro_preview_exited'
      group by 1, 2
    )
    select coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(a.c, 0)) order by ds.day), '[]'::jsonb)
    into j_preview_exits
    from day_series ds
    left join agg a on a.day = ds.day;

    with day_series as (
      select generate_series(series_from_date, day_start_date, interval '1 day')::date as day
    ),
    agg as (
      select (date_trunc('day', timezone('utc', pe.occurred_at)))::date as day,
             count(*)::int as c
      from public.product_events pe
      where pe.occurred_at >= series_from
        and pe.event_name = 'traxspro_preview_upgrade_tapped'
      group by 1
    )
    select coalesce(jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(a.c, 0)) order by ds.day), '[]'::jsonb)
    into j_preview_upgrades
    from day_series ds
    left join agg a on a.day = ds.day;

    select
      count(*) filter (where pe.event_name = 'traxspro_preview_started')::int,
      count(*) filter (where pe.event_name = 'traxspro_preview_exited')::int,
      count(*) filter (where pe.event_name = 'traxspro_preview_upgrade_tapped')::int
    into v_preview_starts, v_preview_exits, v_preview_upgrades
    from public.product_events pe
    where pe.occurred_at >= series_from
      and pe.event_name in (
        'traxspro_preview_started',
        'traxspro_preview_exited',
        'traxspro_preview_upgrade_tapped'
      );

    if v_preview_starts > 0 then
      v_preview_rate := round(100.0 * v_preview_upgrades / v_preview_starts, 2);
    end if;
  else
    j_preview_starts := '[]'::jsonb;
    j_preview_exits := '[]'::jsonb;
    j_preview_upgrades := '[]'::jsonb;
    v_notes := array_append(v_notes, 'TraxsPro preview funnel requires product_events (phase 1).');
  end if;

  v_notes := array_append(
    v_notes,
    'Active traders exclude Tradovate/Rithmic bulk initial imports so broker sync does not inflate trader counts.'
  );

  return jsonb_build_object(
    'seriesDays', series_days,
    'meta', jsonb_build_object(
      'productTrackingStartDate', v_tracking_start,
      'productEngagementAvailable', v_engagement_available,
      'retentionMetricsAvailable', v_retention_available,
      'previewFunnelAvailable', v_preview_available,
      'notes', to_jsonb(v_notes)
    ),
    'overview', jsonb_build_object(
      'totalUsers', v_total_users,
      'newSignupsToday', v_new_today,
      'productDau', case when v_engagement_available then v_product_dau else null end,
      'productWau', case when v_engagement_available then v_product_wau else null end,
      'productMau', case when v_engagement_available then v_product_mau else null end,
      'dauMauRatio', v_dau_mau
    ),
    'growth', jsonb_build_object(
      'signupsPerDay', j_signups,
      'productActiveUsersPerDay', coalesce(j_product_dau, '[]'::jsonb)
    ),
    'retention', jsonb_build_object(
      'd1Rate', v_d1,
      'd7Rate', v_d7,
      'd30Rate', v_d30,
      'returningUsersPerDay', coalesce(j_returning, '[]'::jsonb),
      'cohortSampleSignups', v_cohort_sample
    ),
    'trading', jsonb_build_object(
      'tradesCreatedPerDay', j_trades,
      'activeTradersPerDay', j_traders,
      'tradesPerActiveTraderLatestDay', v_trades_per_trader,
      'importTotalsInPeriod', coalesce(j_import_totals, jsonb_build_object('manual', 0, 'csv', 0, 'broker', 0, 'other', 0))
    ),
    'social', jsonb_build_object(
      'profileViewsPerDay', coalesce(j_profile_views, '[]'::jsonb),
      'uniqueProfileViewersPerDay', coalesce(j_unique_viewers, '[]'::jsonb),
      'postsPerDay', j_posts,
      'featureEngagementPerDay', coalesce(j_feature_engagement, '[]'::jsonb)
    ),
    'features', jsonb_build_object(
      'topFeatures', coalesce(j_top_features, '[]'::jsonb)
    ),
    'traxsProPreview', jsonb_build_object(
      'available', v_preview_available,
      'startsPerDay', coalesce(j_preview_starts, '[]'::jsonb),
      'exitsPerDay', coalesce(j_preview_exits, '[]'::jsonb),
      'upgradeTapsPerDay', coalesce(j_preview_upgrades, '[]'::jsonb),
      'funnelTotals', jsonb_build_object(
        'starts', v_preview_starts,
        'exits', v_preview_exits,
        'upgradeTaps', v_preview_upgrades,
        'startToUpgradeRate', v_preview_rate
      )
    )
  );
end;
$$;

revoke all on function public.admin_product_analytics_bundle(int) from public;
grant execute on function public.admin_product_analytics_bundle(int) to authenticated;