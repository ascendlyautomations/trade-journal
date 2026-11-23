-- Admin lifecycle analytics: activation funnel, TraxsPro conversion, session retention & subscriber churn.
-- Parallel to existing admin_* bundles; admin-only via admin_users check.

create or replace function public.admin_lifecycle_analytics_bundle(
  p_series_days int default null,
  p_start_date date default null,
  p_end_date date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller_user_id uuid := auth.uid();
  v_today date := (date_trunc('day', timezone('utc', now())))::date;
  series_days int;
  period_start_date date;
  period_end_date date;
  series_from timestamptz;
  series_to timestamptz;
  v_range_mode text := 'preset';
  v_tracking_start date;
  v_engagement_available boolean := false;
  v_events_available boolean := false;
  v_notes text[] := array[]::text[];
  v_signups bigint := 0;
  v_onboarding bigint := 0;
  v_first_account bigint := 0;
  v_first_trade bigint := 0;
  v_first_social bigint := 0;
  v_first_return bigint := 0;
  v_med_onboarding_hours numeric;
  v_med_account_hours numeric;
  v_med_trade_hours numeric;
  v_med_social_hours numeric;
  v_med_return_hours numeric;
  v_insufficient_activation boolean := false;
  v_free_engaged bigint := 0;
  v_preview_dashboard bigint := 0;
  v_preview_reports bigint := 0;
  v_preview_expense bigint := 0;
  v_paywall_views bigint := 0;
  v_paywall_web bigint := 0;
  v_paywall_ios bigint := 0;
  v_upgrade_clicks bigint := 0;
  v_upgrade_web bigint := 0;
  v_upgrade_ios bigint := 0;
  v_preview_starts bigint := 0;
  v_preview_upgrade_taps bigint := 0;
  v_trials_started bigint := 0;
  v_new_paid bigint := 0;
  v_cancellations bigint := 0;
  v_expired_apple bigint := 0;
  v_d1 numeric;
  v_d7 numeric;
  v_d30 numeric;
  v_cohort_sample int := 0;
  v_d1_mature int := 0;
  v_d7_mature int := 0;
  v_d30_mature int := 0;
  v_retention_insufficient boolean := false;
  v_inactive_7 bigint := 0;
  v_inactive_14 bigint := 0;
  v_inactive_30 bigint := 0;
  v_subs_at_start bigint := 0;
  v_subs_at_end bigint := 0;
  v_sub_churn_rate numeric;
  j_weekly_returning jsonb;
  j_new_vs_returning jsonb;
  j_stages_activation jsonb;
  j_stages_traxspro jsonb;
  j_median_hours jsonb;
begin
  if caller_user_id is null or not exists (
    select 1 from public.admin_users au where au.user_id = caller_user_id
  ) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  if p_start_date is not null or p_end_date is not null then
    if p_start_date is null or p_end_date is null then
      raise exception 'custom range requires p_start_date and p_end_date' using errcode = '22023';
    end if;
    if p_start_date > p_end_date then
      raise exception 'invalid date range' using errcode = '22023';
    end if;
    if p_end_date > v_today or p_start_date > v_today then
      raise exception 'dates cannot be in the future (utc)' using errcode = '22023';
    end if;
  if (p_end_date - p_start_date) > 364 then
      raise exception 'custom range cannot exceed 365 days' using errcode = '22023';
    end if;
    v_range_mode := 'custom';
    period_start_date := p_start_date;
    period_end_date := p_end_date;
    series_days := (p_end_date - p_start_date) + 1;
  else
    series_days := greatest(1, least(coalesce(p_series_days, 90), 365));
    period_end_date := v_today;
    period_start_date := period_end_date - (series_days - 1);
    v_range_mode := 'preset';
  end if;

  series_from := (period_start_date::text || ' 00:00:00+00')::timestamptz;
  series_to := ((period_end_date + 1)::text || ' 00:00:00+00')::timestamptz;

  v_notes := array_append(v_notes, 'Activation milestones use signup cohorts in the selected UTC window (not retroactive session data).');
  v_notes := array_append(v_notes, 'Session retention uses product_daily_user_activity only — separate from Historical Engagement content retention.');
  v_notes := array_append(v_notes, 'Paid conversions use Stripe profile fields and verified apple_subscriptions — upgrade clicks do not count as subscriptions.');
  v_notes := array_append(v_notes, 'Expense Tracker preview funnel awaits product events (no interactive preview shipped yet).');

  if to_regclass('public.product_daily_user_activity') is not null then
    select min(pdua.activity_day) into v_tracking_start
    from public.product_daily_user_activity pdua
    where pdua.engaged;
    v_engagement_available := v_tracking_start is not null;
    if not v_engagement_available then
      v_notes := array_append(v_notes, 'No product engagement rollups yet; session retention and return-visit activation are limited.');
    end if;
  else
    v_notes := array_append(v_notes, 'Product engagement rollups missing; session metrics unavailable.');
  end if;

  v_events_available := to_regclass('public.product_events') is not null;
  if not v_events_available then
    v_notes := array_append(v_notes, 'TraxsPro funnel events require product_events (phase 1).');
  end if;

  -- Activation funnel (signup cohort in period)
  with cohort as (
    select
      p.id as user_id,
      p.created_at as signup_at,
      (date_trunc('day', timezone('utc', coalesce(p.created_at, now()))))::date as signup_day,
      coalesce(p.onboarding_completed, false) as onboarding_flag
    from public.profiles p
    where coalesce(p.created_at, now()) >= series_from
      and coalesce(p.created_at, now()) < series_to
  ),
  agg as (
    select
      count(*)::bigint as signups,
      count(*) filter (
        where c.onboarding_flag
          or exists (
            select 1
            from public.product_events pe
            where pe.user_id = c.user_id
              and pe.event_name = 'milestone_onboarding_completed'
          )
      )::bigint as onboarding_done,
      count(*) filter (
        where exists (
          select 1
          from public.accounts a
          where a.user_id = c.user_id
            and a.created_at is not null
        )
      )::bigint as first_account,
      count(*) filter (
        where exists (
          select 1
          from public.trades t
          where t.user_id = c.user_id
            and not coalesce(t.is_initial_import, false)
            and t.created_at is not null
        )
      )::bigint as first_trade,
      count(*) filter (
        where exists (
          select 1
          from public.posts po
          where po.user_id = c.user_id and po.created_at is not null
        )
        or exists (
          select 1 from public.profile_posts pp
          where pp.user_id = c.user_id and pp.created_at is not null
        )
        or exists (
          select 1 from public.reels r
          where r.user_id = c.user_id and r.created_at is not null
        )
        or exists (
          select 1 from public.comments cm
          where cm.user_id = c.user_id and cm.created_at is not null
        )
        or exists (
          select 1 from public.likes l
          where l.user_id = c.user_id and l.created_at is not null
        )
        or exists (
          select 1 from public.followers f
          where f.follower_id = c.user_id and f.created_at is not null
        )
        or exists (
          select 1 from public.messages m
          where m.sender_id = c.user_id and m.created_at is not null
        )
      )::bigint as first_social,
      count(*) filter (
        where v_engagement_available
          and exists (
            select 1
            from public.product_daily_user_activity pdua
            where pdua.user_id = c.user_id
              and pdua.engaged
              and pdua.activity_day > c.signup_day
              and v_tracking_start is not null
              and pdua.activity_day >= v_tracking_start
          )
      )::bigint as first_return
    from cohort c
  )
  select signups, onboarding_done, first_account, first_trade, first_social, first_return
  into v_signups, v_onboarding, v_first_account, v_first_trade, v_first_social, v_first_return
  from agg;

  v_insufficient_activation := coalesce(v_signups, 0) < 5;

  with cohort as (
    select p.id as user_id, p.created_at as signup_at, coalesce(p.onboarding_completed, false) as onboarding_flag
    from public.profiles p
    where coalesce(p.created_at, now()) >= series_from
      and coalesce(p.created_at, now()) < series_to
  ),
  onboarding_at as (
    select c.user_id,
           coalesce(
             (select min(pe.occurred_at)
              from public.product_events pe
              where pe.user_id = c.user_id
                and pe.event_name = 'milestone_onboarding_completed'),
             case when c.onboarding_flag then c.signup_at else null end
           ) as at
    from cohort c
  ),
  account_at as (
    select c.user_id, min(a.created_at) as at
    from cohort c
    join public.accounts a on a.user_id = c.user_id
    group by c.user_id
  ),
  trade_at as (
    select c.user_id, min(t.created_at) as at
    from cohort c
    join public.trades t on t.user_id = c.user_id and not coalesce(t.is_initial_import, false)
    group by c.user_id
  ),
  social_at as (
    select
      c.user_id,
      (
        select min(v)
        from unnest(
          array[
            (select min(po.created_at) from public.posts po where po.user_id = c.user_id),
            (select min(pp.created_at) from public.profile_posts pp where pp.user_id = c.user_id),
            (select min(r.created_at) from public.reels r where r.user_id = c.user_id),
            (select min(cm.created_at) from public.comments cm where cm.user_id = c.user_id),
            (select min(l.created_at) from public.likes l where l.user_id = c.user_id),
            (select min(f.created_at) from public.followers f where f.follower_id = c.user_id),
            (select min(m.created_at) from public.messages m where m.sender_id = c.user_id)
          ]
        ) as u(v)
        where v is not null
      ) as at
    from cohort c
  ),
  return_at as (
    select c.user_id,
           min(pdua.activity_day::timestamptz) as at
    from cohort c
    join public.product_daily_user_activity pdua
      on pdua.user_id = c.user_id
     and pdua.engaged
     and pdua.activity_day > (date_trunc('day', timezone('utc', c.signup_at)))::date
    where v_engagement_available
    group by c.user_id
  )
  select
    round(percentile_cont(0.5) within group (order by extract(epoch from (oa.at - c.signup_at)) / 3600.0)::numeric, 2),
    round(percentile_cont(0.5) within group (order by extract(epoch from (aa.at - c.signup_at)) / 3600.0)::numeric, 2),
    round(percentile_cont(0.5) within group (order by extract(epoch from (ta.at - c.signup_at)) / 3600.0)::numeric, 2),
    round(percentile_cont(0.5) within group (order by extract(epoch from (sa.at - c.signup_at)) / 3600.0)::numeric, 2),
    round(percentile_cont(0.5) within group (order by extract(epoch from (ra.at - c.signup_at)) / 3600.0)::numeric, 2)
  into v_med_onboarding_hours, v_med_account_hours, v_med_trade_hours, v_med_social_hours, v_med_return_hours
  from cohort c
  left join onboarding_at oa on oa.user_id = c.user_id and oa.at is not null
  left join account_at aa on aa.user_id = c.user_id and aa.at is not null
  left join trade_at ta on ta.user_id = c.user_id and ta.at is not null
  left join social_at sa on sa.user_id = c.user_id and sa.at is not null
  left join return_at ra on ra.user_id = c.user_id and ra.at is not null;

  j_median_hours := jsonb_build_object(
    'onboarding', v_med_onboarding_hours,
    'firstAccount', v_med_account_hours,
    'firstTrade', v_med_trade_hours,
    'firstSocial', v_med_social_hours,
    'firstReturnVisit', case when v_engagement_available then v_med_return_hours else null end
  );

  j_stages_activation := jsonb_build_array(
    jsonb_build_object('id', 'signup', 'label', 'Signups', 'count', v_signups, 'conversionFromSignupPct', 100, 'dropOffFromPriorPct', 0),
    jsonb_build_object(
      'id', 'onboarding',
      'label', 'Onboarding complete',
      'count', v_onboarding,
      'conversionFromSignupPct', case when v_signups > 0 then round(100.0 * v_onboarding / v_signups, 2) else null end,
      'dropOffFromPriorPct', case when v_signups > 0 then round(100.0 * (v_signups - v_onboarding) / v_signups, 2) else null end
    ),
    jsonb_build_object(
      'id', 'first_account',
      'label', 'First trading account',
      'count', v_first_account,
      'conversionFromSignupPct', case when v_signups > 0 then round(100.0 * v_first_account / v_signups, 2) else null end,
      'dropOffFromPriorPct', case when v_onboarding > 0 then round(100.0 * (v_onboarding - v_first_account) / v_onboarding, 2) else null end
    ),
    jsonb_build_object(
      'id', 'first_trade',
      'label', 'First trade logged',
      'count', v_first_trade,
      'conversionFromSignupPct', case when v_signups > 0 then round(100.0 * v_first_trade / v_signups, 2) else null end,
      'dropOffFromPriorPct', case when v_first_account > 0 then round(100.0 * (v_first_account - v_first_trade) / v_first_account, 2) else null end
    ),
    jsonb_build_object(
      'id', 'first_social',
      'label', 'First social interaction',
      'count', v_first_social,
      'conversionFromSignupPct', case when v_signups > 0 then round(100.0 * v_first_social / v_signups, 2) else null end,
      'dropOffFromPriorPct', case when v_first_trade > 0 then round(100.0 * (v_first_trade - v_first_social) / v_first_trade, 2) else null end
    ),
    jsonb_build_object(
      'id', 'first_return',
      'label', 'First return visit (tracked sessions)',
      'count', v_first_return,
      'conversionFromSignupPct', case when v_signups > 0 then round(100.0 * v_first_return / v_signups, 2) else null end,
      'dropOffFromPriorPct', case when v_first_social > 0 then round(100.0 * (v_first_social - v_first_return) / v_first_social, 2) else null end,
      'awaitingData', not v_engagement_available
    )
  );

  if v_events_available then
    select count(distinct pdua.user_id)::bigint
    into v_free_engaged
    from public.product_daily_user_activity pdua
    join public.profiles p on p.id = pdua.user_id
    where pdua.engaged
      and pdua.activity_day >= period_start_date
      and pdua.activity_day <= period_end_date
      and not public.profile_is_pro_user(p.id);

    select
      count(distinct pe.user_id) filter (
        where pe.event_name = 'traxspro_preview_started'
          and coalesce(pe.props ->> 'preview_feature', '') = 'dashboard'
      )::bigint,
      count(distinct pe.user_id) filter (
        where pe.event_name = 'traxspro_preview_started'
          and coalesce(pe.props ->> 'preview_feature', '') = 'reports'
      )::bigint,
      count(distinct pe.user_id) filter (
        where pe.event_name = 'traxspro_preview_started'
          and coalesce(pe.props ->> 'preview_feature', '') = 'expense_tracker'
      )::bigint,
      count(distinct pe.user_id) filter (where pe.event_name = 'paywall_viewed')::bigint,
      count(distinct pe.user_id) filter (where pe.event_name = 'paywall_viewed' and pe.platform = 'web')::bigint,
      count(distinct pe.user_id) filter (where pe.event_name = 'paywall_viewed' and pe.platform = 'ios')::bigint,
      count(distinct pe.user_id) filter (
        where pe.event_name in ('monetization_upgrade_clicked', 'traxspro_preview_upgrade_tapped')
      )::bigint,
      count(distinct pe.user_id) filter (
        where pe.event_name in ('monetization_upgrade_clicked', 'traxspro_preview_upgrade_tapped')
          and pe.platform = 'web'
      )::bigint,
      count(distinct pe.user_id) filter (
        where pe.event_name in ('monetization_upgrade_clicked', 'traxspro_preview_upgrade_tapped')
          and pe.platform = 'ios'
      )::bigint,
      count(distinct pe.user_id) filter (where pe.event_name = 'traxspro_preview_started')::bigint,
      count(distinct pe.user_id) filter (where pe.event_name = 'traxspro_preview_upgrade_tapped')::bigint
    into
      v_preview_dashboard,
      v_preview_reports,
      v_preview_expense,
      v_paywall_views,
      v_paywall_web,
      v_paywall_ios,
      v_upgrade_clicks,
      v_upgrade_web,
      v_upgrade_ios,
      v_preview_starts,
      v_preview_upgrade_taps
    from public.product_events pe
    where pe.occurred_at >= series_from
      and pe.occurred_at < series_to;
  end if;

  select count(distinct p.id)::bigint
  into v_trials_started
  from public.profiles p
  where lower(trim(coalesce(p.subscription_status, ''))) = 'trialing'
    and p.trial_end is not null
    and (timezone('utc', p.trial_end))::date >= period_start_date
    and (timezone('utc', p.trial_end))::date <= period_end_date + 14;

  select count(distinct a.user_id)::bigint
  into v_new_paid
  from public.apple_subscriptions a
  where a.purchased_at is not null
    and a.purchased_at >= series_from
    and a.purchased_at < series_to;

  select count(distinct p.id)::bigint
  into v_cancellations
  from public.profiles p
  where p.cancel_at is not null
    and (timezone('utc', p.cancel_at))::date >= period_start_date
    and (timezone('utc', p.cancel_at))::date <= period_end_date;

  if to_regclass('public.apple_subscriptions') is not null then
    select count(distinct a.user_id)::bigint
    into v_expired_apple
    from public.apple_subscriptions a
    where a.status = 'expired'
      and a.updated_at >= series_from
      and a.updated_at < series_to;
  end if;

  j_stages_traxspro := jsonb_build_array(
    jsonb_build_object('id', 'free_engaged', 'label', 'Free users (tracked engagement)', 'count', coalesce(v_free_engaged, 0), 'awaitingData', not v_engagement_available),
    jsonb_build_object('id', 'preview_dashboard', 'label', 'Dashboard preview starts', 'count', coalesce(v_preview_dashboard, 0), 'awaitingData', not v_events_available),
    jsonb_build_object('id', 'preview_reports', 'label', 'Reports preview starts', 'count', coalesce(v_preview_reports, 0), 'awaitingData', not v_events_available),
    jsonb_build_object('id', 'preview_expense', 'label', 'Expense Tracker preview starts', 'count', coalesce(v_preview_expense, 0), 'awaitingData', true),
    jsonb_build_object('id', 'paywall_viewed', 'label', 'Paywall views', 'count', coalesce(v_paywall_views, 0), 'awaitingData', not v_events_available),
    jsonb_build_object('id', 'upgrade_clicks', 'label', 'Upgrade button clicks', 'count', coalesce(v_upgrade_clicks, 0), 'awaitingData', not v_events_available),
    jsonb_build_object('id', 'trials_started', 'label', 'Trial starts (billing)', 'count', coalesce(v_trials_started, 0)),
    jsonb_build_object('id', 'new_subscriptions', 'label', 'New subscriptions (billing)', 'count', coalesce(v_new_paid, 0)),
    jsonb_build_object('id', 'cancellations', 'label', 'Cancellations / expired', 'count', coalesce(v_cancellations, 0) + coalesce(v_expired_apple, 0))
  );

  if v_engagement_available then
    with cohorts as (
      select p.id as user_id,
             (date_trunc('day', timezone('utc', coalesce(p.created_at, now()))))::date as signup_day
      from public.profiles p
      where (date_trunc('day', timezone('utc', coalesce(p.created_at, now()))))::date
            >= greatest(v_tracking_start, period_start_date - 60)
        and (date_trunc('day', timezone('utc', coalesce(p.created_at, now()))))::date
            <= period_end_date - 1
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
             (period_end_date - c.signup_day) as age_days
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
    into v_cohort_sample, v_d1_mature, v_d7_mature, v_d30_mature, v_d1, v_d7, v_d30
    from scored;

    v_retention_insufficient := coalesce(v_d1_mature, 0) < 5;

    with weeks as (
      select generate_series(
        date_trunc('week', period_start_date::timestamp)::date,
        period_end_date,
        interval '7 days'
      )::date as week_start
    ),
    week_ends as (
      select week_start, least(week_start + 6, period_end_date) as week_end
      from weeks
    ),
    counts as (
      select we.week_end as day,
             count(distinct pdua.user_id)::bigint as c
      from week_ends we
      join public.product_daily_user_activity pdua
        on pdua.activity_day >= we.week_start
       and pdua.activity_day <= we.week_end
       and pdua.engaged
       and pdua.activity_day >= v_tracking_start
      where exists (
        select 1
        from public.product_daily_user_activity prior
        where prior.user_id = pdua.user_id
          and prior.engaged
          and prior.activity_day < we.week_start
      )
      group by we.week_end
    )
    select coalesce(
      jsonb_agg(jsonb_build_object('day', c.day::text, 'count', c.c) order by c.day),
      '[]'::jsonb
    )
    into j_weekly_returning
    from counts c;

    with day_series as (
      select generate_series(
        greatest(period_start_date, v_tracking_start),
        period_end_date,
        interval '1 day'
      )::date as day
    ),
    new_users as (
      select pdua.activity_day as day,
             count(distinct pdua.user_id)::bigint as c
      from public.product_daily_user_activity pdua
      where pdua.engaged
        and pdua.activity_day >= greatest(period_start_date, v_tracking_start)
        and pdua.activity_day <= period_end_date
        and not exists (
          select 1
          from public.product_daily_user_activity prior
          where prior.user_id = pdua.user_id
            and prior.engaged
            and prior.activity_day < pdua.activity_day
        )
      group by 1
    ),
    returning_users as (
      select pdua.activity_day as day,
             count(distinct pdua.user_id)::bigint as c
      from public.product_daily_user_activity pdua
      where pdua.engaged
        and pdua.activity_day >= greatest(period_start_date, v_tracking_start)
        and pdua.activity_day <= period_end_date
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
      jsonb_agg(
        jsonb_build_object(
          'day', ds.day::text,
          'newUsers', coalesce(nu.c, 0),
          'returningUsers', coalesce(ru.c, 0)
        )
        order by ds.day
      ),
      '[]'::jsonb
    )
    into j_new_vs_returning
    from day_series ds
    left join new_users nu on nu.day = ds.day
    left join returning_users ru on ru.day = ds.day;

    select count(distinct pdua.user_id)::bigint
    into v_inactive_7
    from public.product_daily_user_activity pdua
    where pdua.engaged
      and pdua.activity_day < period_end_date - 6
      and pdua.activity_day >= v_tracking_start
      and not exists (
        select 1
        from public.product_daily_user_activity recent
        where recent.user_id = pdua.user_id
          and recent.engaged
          and recent.activity_day >= period_end_date - 6
          and recent.activity_day <= period_end_date
      );

    select count(distinct pdua.user_id)::bigint
    into v_inactive_14
    from public.product_daily_user_activity pdua
    where pdua.engaged
      and pdua.activity_day < period_end_date - 13
      and pdua.activity_day >= v_tracking_start
      and not exists (
        select 1
        from public.product_daily_user_activity recent
        where recent.user_id = pdua.user_id
          and recent.engaged
          and recent.activity_day >= period_end_date - 13
          and recent.activity_day <= period_end_date
      );

    select count(distinct pdua.user_id)::bigint
    into v_inactive_30
    from public.product_daily_user_activity pdua
    where pdua.engaged
      and pdua.activity_day < period_end_date - 29
      and pdua.activity_day >= v_tracking_start
      and not exists (
        select 1
        from public.product_daily_user_activity recent
        where recent.user_id = pdua.user_id
          and recent.engaged
          and recent.activity_day >= period_end_date - 29
          and recent.activity_day <= period_end_date
      );
  else
    j_weekly_returning := '[]'::jsonb;
    j_new_vs_returning := '[]'::jsonb;
  end if;

  select count(distinct p.id)::bigint
  into v_subs_at_end
  from public.profiles p
  where public.profile_is_pro_user(p.id);

  v_subs_at_start := null;
  v_sub_churn_rate := null;

  v_notes := array_append(
    v_notes,
    'Trial starts approximate profiles in trialing state with trial_end overlapping the period — exact trial start time is not stored server-side.'
  );
  v_notes := array_append(
    v_notes,
    'Subscriber headcount at period start is unavailable without subscription history snapshots; churn uses cancellations and Apple expirations in period.'
  );

  return jsonb_build_object(
    'seriesDays', series_days,
    'meta', jsonb_build_object(
      'periodStart', period_start_date::text,
      'periodEnd', period_end_date::text,
      'rangeMode', v_range_mode,
      'productTrackingStartDate', v_tracking_start,
      'sessionMetricsAvailable', v_engagement_available,
      'productEventsAvailable', v_events_available,
      'notes', to_jsonb(v_notes)
    ),
    'userGrowthActivation', jsonb_build_object(
      'cohortSignups', v_signups,
      'insufficientData', v_insufficient_activation,
      'stages', j_stages_activation,
      'medianHoursToStage', j_median_hours
    ),
    'traxsProConversion', jsonb_build_object(
      'stages', j_stages_traxspro,
      'platform', jsonb_build_object(
        'paywallViews', jsonb_build_object('web', coalesce(v_paywall_web, 0), 'ios', coalesce(v_paywall_ios, 0)),
        'upgradeClicks', jsonb_build_object('web', coalesce(v_upgrade_web, 0), 'ios', coalesce(v_upgrade_ios, 0)),
        'previewStarts', jsonb_build_object('total', coalesce(v_preview_starts, 0))
      ),
      'previewStartsByFeature', jsonb_build_object(
        'dashboard', coalesce(v_preview_dashboard, 0),
        'reports', coalesce(v_preview_reports, 0),
        'expenseTracker', coalesce(v_preview_expense, 0)
      ),
      'billingInPeriod', jsonb_build_object(
        'trials', coalesce(v_trials_started, 0),
        'newSubscriptions', coalesce(v_new_paid, 0),
        'cancellations', coalesce(v_cancellations, 0),
        'appleExpired', coalesce(v_expired_apple, 0)
      )
    ),
    'retentionChurn', jsonb_build_object(
      'sessionRetention', jsonb_build_object(
        'd1Rate', v_d1,
        'd7Rate', v_d7,
        'd30Rate', v_d30,
        'cohortSampleSignups', v_cohort_sample,
        'd1MatureCohortSize', v_d1_mature,
        'd7MatureCohortSize', v_d7_mature,
        'd30MatureCohortSize', v_d30_mature,
        'insufficientData', v_retention_insufficient,
        'definition', 'Session retention from product_daily_user_activity (UTC). Content-based retention is under Historical Engagement.'
      ),
      'weeklyReturningUsers', coalesce(j_weekly_returning, '[]'::jsonb),
      'newVsReturningUsersPerDay', coalesce(j_new_vs_returning, '[]'::jsonb),
      'inactiveUsers', jsonb_build_object(
        'inactive7Days', coalesce(v_inactive_7, 0),
        'inactive14Days', coalesce(v_inactive_14, 0),
        'inactive30Days', coalesce(v_inactive_30, 0),
        'asOfDate', period_end_date::text
      ),
      'subscriberChurn', jsonb_build_object(
        'activeSubscribersAtPeriodStart', v_subs_at_start,
        'activeSubscribersAtPeriodEnd', coalesce(v_subs_at_end, 0),
        'grossChurnRatePct', v_sub_churn_rate,
        'insufficientData', true,
        'definition', 'Paid churn uses cancel_at on profiles and Apple subscription expirations. Current Pro headcount is a point-in-time snapshot only.'
      )
    )
  );
end;
$$;

revoke all on function public.admin_lifecycle_analytics_bundle(int, date, date) from public;
grant execute on function public.admin_lifecycle_analytics_bundle(int, date, date) to authenticated;