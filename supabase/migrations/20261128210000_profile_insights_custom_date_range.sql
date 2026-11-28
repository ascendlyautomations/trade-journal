-- Profile Insights: optional custom UTC date range (p_start / p_end) alongside preset p_days.
-- Prior-period comparison uses the immediately preceding window of equal length.

drop function if exists public.rpc_v1_profile_insights_bootstrap(integer);

create or replace function public.rpc_v1_profile_insights_bootstrap(
  p_days integer default null,
  p_start date default null,
  p_end date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_days integer;
  v_span integer;
  v_today date := (timezone('utc', now()))::date;
  v_end date;
  v_start date;
  v_prior_end date;
  v_prior_start date;
  j_profile_views jsonb := '[]'::jsonb;
  j_unique_visitors jsonb := '[]'::jsonb;
  j_content_views jsonb := '[]'::jsonb;
  j_net_followers jsonb := '[]'::jsonb;
  j_new_followers_series jsonb := '[]'::jsonb;
  j_unfollows_series jsonb := '[]'::jsonb;
  v_profile_views bigint := 0;
  v_unique_visitors bigint := 0;
  v_profile_views_prior bigint := 0;
  v_unique_prior bigint := 0;
  v_content_views bigint := 0;
  v_content_unique bigint := 0;
  v_content_views_prior bigint := 0;
  v_new_followers int := 0;
  v_unfollows int := 0;
  v_new_followers_prior int := 0;
  v_unfollows_prior int := 0;
  v_likes bigint := 0;
  v_comments bigint := 0;
  v_saves bigint := 0;
  v_shares_initiated bigint := 0;
  v_shares_completed bigint := 0;
  v_engagement bigint := 0;
  v_engagement_prior bigint := 0;
  v_story_views bigint := 0;
  v_story_views_prior bigint := 0;
  j_by_kind jsonb := '{}'::jsonb;
  j_top jsonb := '[]'::jsonb;
  j_top_views jsonb := '[]'::jsonb;
  j_top_engagement jsonb := '[]'::jsonb;
  v_profile_since timestamptz;
  v_content_since timestamptz;
  v_follower_events_since timestamptz;
  v_shares_since timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_start is not null and p_end is not null then
    v_start := least(p_start, p_end);
    v_end := greatest(p_start, p_end);
    v_end := least(v_end, v_today);
    if v_start > v_end then
      v_start := v_end;
    end if;
    v_span := (v_end - v_start) + 1;
    if v_span > 366 then
      v_start := v_end - 365;
      v_span := 366;
    end if;
    v_days := v_span;
    v_prior_end := v_start - 1;
    v_prior_start := v_prior_end - (v_span - 1);
  else
    v_days := greatest(7, least(coalesce(p_days, 30), 90));
    v_end := v_today;
    v_start := v_end - (v_days - 1);
    v_prior_end := v_start - 1;
    v_prior_start := v_prior_end - (v_days - 1);
  end if;

  select min(pv.activity_day)::timestamptz
  into v_profile_since
  from public.product_daily_profile_views pv
  where pv.viewed_profile_id = v_uid;

  select min(c.activity_day)::timestamptz
  into v_content_since
  from public.creator_content_views_daily c
  where c.creator_id = v_uid;

  select min(e.occurred_at)
  into v_follower_events_since
  from public.creator_follower_events e
  where e.creator_id = v_uid;

  select min(s.occurred_at)
  into v_shares_since
  from public.creator_share_events s
  where s.creator_id = v_uid;

  if to_regclass('public.product_daily_profile_views') is not null then
    select coalesce(sum(pv.view_count), 0)
    into v_profile_views
    from public.product_daily_profile_views pv
    where pv.viewed_profile_id = v_uid
      and pv.activity_day between v_start and v_end;

    select count(distinct u.viewer_id)::bigint
    into v_unique_visitors
    from public.product_profile_view_uniques u
    where u.viewed_profile_id = v_uid
      and u.activity_day between v_start and v_end;

    select coalesce(sum(pv.view_count), 0)
    into v_profile_views_prior
    from public.product_daily_profile_views pv
    where pv.viewed_profile_id = v_uid
      and pv.activity_day between v_prior_start and v_prior_end;

    select count(distinct u.viewer_id)::bigint
    into v_unique_prior
    from public.product_profile_view_uniques u
    where u.viewed_profile_id = v_uid
      and u.activity_day between v_prior_start and v_prior_end;

    with day_series as (
      select generate_series(v_start, v_end, interval '1 day')::date as day
    )
    select coalesce(
      jsonb_agg(
        jsonb_build_object('day', ds.day::text, 'count', coalesce(pv.view_count, 0))
        order by ds.day
      ),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object('day', ds.day::text, 'count', coalesce(pv.unique_viewer_count, 0))
        order by ds.day
      ),
      '[]'::jsonb
    )
    into j_profile_views, j_unique_visitors
    from day_series ds
    left join public.product_daily_profile_views pv
      on pv.viewed_profile_id = v_uid and pv.activity_day = ds.day;
  end if;

  select coalesce(sum(c.view_count), 0)
  into v_content_views
  from public.creator_content_views_daily c
  where c.creator_id = v_uid and c.activity_day between v_start and v_end;

  select coalesce(sum(u.cnt), 0)
  into v_content_unique
  from (
    select count(distinct u.viewer_id) as cnt
    from public.creator_content_view_uniques u
    where u.creator_id = v_uid and u.activity_day between v_start and v_end
  ) u;

  select coalesce(sum(c.view_count), 0)
  into v_content_views_prior
  from public.creator_content_views_daily c
  where c.creator_id = v_uid and c.activity_day between v_prior_start and v_prior_end;

  with day_series as (
    select generate_series(v_start, v_end, interval '1 day')::date as day
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object('day', ds.day::text, 'count', coalesce(x.views, 0))
      order by ds.day
    ),
    '[]'::jsonb
  )
  into j_content_views
  from day_series ds
  left join (
    select c.activity_day as day, sum(c.view_count)::bigint as views
    from public.creator_content_views_daily c
    where c.creator_id = v_uid
    group by 1
  ) x on x.day = ds.day;

  select coalesce(
    jsonb_object_agg(k.kind, coalesce(s.views, 0)),
    '{}'::jsonb
  )
  into j_by_kind
  from (values ('post'), ('profile_post'), ('achievement_post'), ('reel')) as k(kind)
  left join (
    select c.content_kind as kind, sum(c.view_count)::bigint as views
    from public.creator_content_views_daily c
    where c.creator_id = v_uid and c.activity_day between v_start and v_end
    group by 1
  ) s on s.kind = k.kind;

  select coalesce(count(*), 0)
  into v_story_views
  from public.story_views sv
  join public.stories st on st.id = sv.story_id
  where st.user_id = v_uid
    and sv.viewer_id <> v_uid
    and (timezone('utc', sv.first_viewed_at))::date between v_start and v_end;

  j_by_kind := coalesce(j_by_kind, '{}'::jsonb)
    || jsonb_build_object('story', v_story_views);

  select coalesce(count(*), 0)
  into v_story_views_prior
  from public.story_views sv
  join public.stories st on st.id = sv.story_id
  where st.user_id = v_uid
    and sv.viewer_id <> v_uid
    and (timezone('utc', sv.first_viewed_at))::date between v_prior_start and v_prior_end;

  select count(*) filter (where e.event_type = 'follow'),
         count(*) filter (where e.event_type = 'unfollow')
  into v_new_followers, v_unfollows
  from public.creator_follower_events e
  where e.creator_id = v_uid
    and (timezone('utc', e.occurred_at))::date between v_start and v_end;

  select count(*) filter (where e.event_type = 'follow'),
         count(*) filter (where e.event_type = 'unfollow')
  into v_new_followers_prior, v_unfollows_prior
  from public.creator_follower_events e
  where e.creator_id = v_uid
    and (timezone('utc', e.occurred_at))::date between v_prior_start and v_prior_end;

  with day_series as (
    select generate_series(v_start, v_end, interval '1 day')::date as day
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(f.new_c, 0) - coalesce(f.un_c, 0)) order by ds.day),
    '[]'::jsonb
  ),
  coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(f.new_c, 0)) order by ds.day),
    '[]'::jsonb
  ),
  coalesce(
    jsonb_agg(jsonb_build_object('day', ds.day::text, 'count', coalesce(f.un_c, 0)) order by ds.day),
    '[]'::jsonb
  )
  into j_net_followers, j_new_followers_series, j_unfollows_series
  from day_series ds
  left join (
    select
      (timezone('utc', e.occurred_at))::date as day,
      count(*) filter (where e.event_type = 'follow') as new_c,
      count(*) filter (where e.event_type = 'unfollow') as un_c
    from public.creator_follower_events e
    where e.creator_id = v_uid
    group by 1
  ) f on f.day = ds.day;

  -- Engagement (exclude self)
  select coalesce(count(*), 0) into v_likes
  from public.likes l
  join public.posts p on p.id = l.post_id
  where p.user_id = v_uid and l.user_id <> v_uid
    and (timezone('utc', l.created_at))::date between v_start and v_end;

  select v_likes + coalesce((
    select count(*) from public.profile_post_likes ppl
    join public.profile_posts pp on pp.id = ppl.profile_post_id
    where pp.user_id = v_uid and ppl.user_id <> v_uid
      and (timezone('utc', ppl.created_at))::date between v_start and v_end
  ), 0)
  + coalesce((
    select count(*) from public.achievement_post_likes apl
    join public.achievement_posts ap on ap.id = apl.achievement_post_id
    where ap.user_id = v_uid and apl.user_id <> v_uid
      and (timezone('utc', apl.created_at))::date between v_start and v_end
  ), 0)
  + coalesce((
    select count(*) from public.reel_likes rl
    join public.reels r on r.id = rl.reel_id
    where r.user_id = v_uid and rl.user_id <> v_uid
      and (timezone('utc', rl.created_at))::date between v_start and v_end
  ), 0)
  + coalesce((
    select count(*) from public.story_likes sl
    join public.stories st on st.id = sl.story_id
    where st.user_id = v_uid and sl.user_id <> v_uid
      and (timezone('utc', sl.created_at))::date between v_start and v_end
  ), 0)
  into v_likes;

  select coalesce(count(*), 0) into v_comments
  from public.comments c
  join public.posts p on p.id = c.post_id
  where p.user_id = v_uid and c.user_id <> v_uid
    and (timezone('utc', c.created_at))::date between v_start and v_end;

  select v_comments
    + coalesce((
      select count(*) from public.profile_post_comments ppc
      join public.profile_posts pp on pp.id = ppc.profile_post_id
      where pp.user_id = v_uid and ppc.user_id <> v_uid
        and (timezone('utc', ppc.created_at))::date between v_start and v_end
    ), 0)
    + coalesce((
      select count(*) from public.achievement_post_comments apc
      join public.achievement_posts ap on ap.id = apc.achievement_post_id
      where ap.user_id = v_uid and apc.user_id <> v_uid
        and (timezone('utc', apc.created_at))::date between v_start and v_end
    ), 0)
    + coalesce((
      select count(*) from public.reel_comments rc
      join public.reels r on r.id = rc.reel_id
      where r.user_id = v_uid and rc.user_id <> v_uid
        and (timezone('utc', rc.created_at))::date between v_start and v_end
    ), 0)
  into v_comments;

  if to_regclass('public.saved_posts') is not null then
  select coalesce(count(*), 0) into v_saves
  from (
    select sp.id
    from public.saved_posts sp
    inner join public.profile_posts pp on pp.id = sp.post_id
    where pp.user_id = v_uid
      and sp.user_id <> v_uid
      and (timezone('utc', sp.created_at))::date between v_start and v_end
    union
    select sp.id
    from public.saved_posts sp
    inner join public.posts p on p.id = sp.post_id
    where p.user_id = v_uid
      and sp.user_id <> v_uid
      and (timezone('utc', sp.created_at))::date between v_start and v_end
      and not exists (
        select 1 from public.profile_posts pp where pp.id = sp.post_id
      )
  ) saves;
  end if;

  select count(*) filter (where s.share_phase = 'initiated'),
         count(*) filter (where s.share_phase = 'completed')
  into v_shares_initiated, v_shares_completed
  from public.creator_share_events s
  where s.creator_id = v_uid
    and (timezone('utc', s.occurred_at))::date between v_start and v_end;

  v_engagement := v_likes + v_comments + v_saves + v_shares_completed;

  select coalesce(count(*), 0)
  into v_engagement_prior
  from public.likes l
  join public.posts p on p.id = l.post_id
  where p.user_id = v_uid and l.user_id <> v_uid
    and (timezone('utc', l.created_at))::date between v_prior_start and v_prior_end;

  select v_engagement_prior
    + coalesce((
      select count(*) from public.profile_post_likes ppl
      join public.profile_posts pp on pp.id = ppl.profile_post_id
      where pp.user_id = v_uid and ppl.user_id <> v_uid
        and (timezone('utc', ppl.created_at))::date between v_prior_start and v_prior_end
    ), 0)
    + coalesce((
      select count(*) from public.achievement_post_likes apl
      join public.achievement_posts ap on ap.id = apl.achievement_post_id
      where ap.user_id = v_uid and apl.user_id <> v_uid
        and (timezone('utc', apl.created_at))::date between v_prior_start and v_prior_end
    ), 0)
    + coalesce((
      select count(*) from public.reel_likes rl
      join public.reels r on r.id = rl.reel_id
      where r.user_id = v_uid and rl.user_id <> v_uid
        and (timezone('utc', rl.created_at))::date between v_prior_start and v_prior_end
    ), 0)
    + coalesce((
      select count(*) from public.story_likes sl
      join public.stories st on st.id = sl.story_id
      where st.user_id = v_uid and sl.user_id <> v_uid
        and (timezone('utc', sl.created_at))::date between v_prior_start and v_prior_end
    ), 0)
  into v_engagement_prior;

  select v_engagement_prior
    + coalesce((
      select count(*) from public.comments c
      join public.posts p on p.id = c.post_id
      where p.user_id = v_uid and c.user_id <> v_uid
        and (timezone('utc', c.created_at))::date between v_prior_start and v_prior_end
    ), 0)
    + coalesce((
      select count(*) from public.profile_post_comments ppc
      join public.profile_posts pp on pp.id = ppc.profile_post_id
      where pp.user_id = v_uid and ppc.user_id <> v_uid
        and (timezone('utc', ppc.created_at))::date between v_prior_start and v_prior_end
    ), 0)
    + coalesce((
      select count(*) from public.achievement_post_comments apc
      join public.achievement_posts ap on ap.id = apc.achievement_post_id
      where ap.user_id = v_uid and apc.user_id <> v_uid
        and (timezone('utc', apc.created_at))::date between v_prior_start and v_prior_end
    ), 0)
    + coalesce((
      select count(*) from public.reel_comments rc
      join public.reels r on r.id = rc.reel_id
      where r.user_id = v_uid and rc.user_id <> v_uid
        and (timezone('utc', rc.created_at))::date between v_prior_start and v_prior_end
    ), 0)
  into v_engagement_prior;

  if to_regclass('public.saved_posts') is not null then
    select v_engagement_prior + coalesce((
      select count(*) from (
        select sp.id
        from public.saved_posts sp
        inner join public.profile_posts pp on pp.id = sp.post_id
        where pp.user_id = v_uid
          and sp.user_id <> v_uid
          and (timezone('utc', sp.created_at))::date between v_prior_start and v_prior_end
        union
        select sp.id
        from public.saved_posts sp
        inner join public.posts p on p.id = sp.post_id
        where p.user_id = v_uid
          and sp.user_id <> v_uid
          and (timezone('utc', sp.created_at))::date between v_prior_start and v_prior_end
          and not exists (
            select 1 from public.profile_posts pp where pp.id = sp.post_id
          )
      ) saves
    ), 0)
    into v_engagement_prior;
  end if;

  select v_engagement_prior + coalesce((
    select count(*) filter (where s.share_phase = 'completed')
    from public.creator_share_events s
    where s.creator_id = v_uid
      and (timezone('utc', s.occurred_at))::date between v_prior_start and v_prior_end
  ), 0)
  into v_engagement_prior;

  with item_views as (
    select
      i.content_kind,
      i.content_id,
      sum(i.view_count)::bigint as views
    from public.creator_content_item_daily i
    where i.creator_id = v_uid and i.activity_day between v_start and v_end
    group by 1, 2
  ),
  item_engagement_parts as (
    select 'post'::text as content_kind, l.post_id as content_id, count(*)::bigint as n
    from public.likes l
    join public.posts p on p.id = l.post_id
    where p.user_id = v_uid and l.user_id <> v_uid
      and (timezone('utc', l.created_at))::date between v_start and v_end
    group by l.post_id
    union all
    select 'post', c.post_id, count(*)::bigint
    from public.comments c
    join public.posts p on p.id = c.post_id
    where p.user_id = v_uid and c.user_id <> v_uid
      and (timezone('utc', c.created_at))::date between v_start and v_end
    group by c.post_id
    union all
    select 'profile_post', l.profile_post_id, count(*)::bigint
    from public.profile_post_likes l
    join public.profile_posts p on p.id = l.profile_post_id
    where p.user_id = v_uid and l.user_id <> v_uid
      and (timezone('utc', l.created_at))::date between v_start and v_end
    group by l.profile_post_id
    union all
    select 'profile_post', c.profile_post_id, count(*)::bigint
    from public.profile_post_comments c
    join public.profile_posts p on p.id = c.profile_post_id
    where p.user_id = v_uid and c.user_id <> v_uid
      and (timezone('utc', c.created_at))::date between v_start and v_end
    group by c.profile_post_id
    union all
    select 'achievement_post', l.achievement_post_id, count(*)::bigint
    from public.achievement_post_likes l
    join public.achievement_posts p on p.id = l.achievement_post_id
    where p.user_id = v_uid and l.user_id <> v_uid
      and (timezone('utc', l.created_at))::date between v_start and v_end
    group by l.achievement_post_id
    union all
    select 'achievement_post', c.achievement_post_id, count(*)::bigint
    from public.achievement_post_comments c
    join public.achievement_posts p on p.id = c.achievement_post_id
    where p.user_id = v_uid and c.user_id <> v_uid
      and (timezone('utc', c.created_at))::date between v_start and v_end
    group by c.achievement_post_id
    union all
    select 'reel', l.reel_id, count(*)::bigint
    from public.reel_likes l
    join public.reels r on r.id = l.reel_id
    where r.user_id = v_uid and l.user_id <> v_uid
      and (timezone('utc', l.created_at))::date between v_start and v_end
    group by l.reel_id
    union all
    select 'reel', c.reel_id, count(*)::bigint
    from public.reel_comments c
    join public.reels r on r.id = c.reel_id
    where r.user_id = v_uid and c.user_id <> v_uid
      and (timezone('utc', c.created_at))::date between v_start and v_end
    group by c.reel_id
    union all
    select s.content_kind, s.content_id, count(*)::bigint
    from public.creator_share_events s
    where s.creator_id = v_uid
      and s.sharer_id <> v_uid
      and s.share_phase = 'completed'
      and (timezone('utc', s.occurred_at))::date between v_start and v_end
    group by s.content_kind, s.content_id
  ),
  item_engagement_saves as (
    select 'profile_post'::text as content_kind, sp.post_id as content_id, count(*)::bigint as n
    from public.saved_posts sp
    inner join public.profile_posts p on p.id = sp.post_id
    where p.user_id = v_uid
      and sp.user_id <> v_uid
      and (timezone('utc', sp.created_at))::date between v_start and v_end
    group by sp.post_id
    union all
    select 'post'::text as content_kind, sp.post_id as content_id, count(*)::bigint as n
    from public.saved_posts sp
    inner join public.posts p on p.id = sp.post_id
    where p.user_id = v_uid
      and sp.user_id <> v_uid
      and (timezone('utc', sp.created_at))::date between v_start and v_end
      and not exists (
        select 1 from public.profile_posts pp where pp.id = sp.post_id
      )
    group by sp.post_id
  ),
  item_engagement_union as (
    select * from item_engagement_parts
    union all
  select * from item_engagement_saves
  ),
  item_engagement as (
    select content_kind, content_id, coalesce(sum(n), 0)::bigint as engagement
    from item_engagement_union
    group by 1, 2
  ),
  combined_items as (
    select
      coalesce(v.content_kind, e.content_kind) as content_kind,
      coalesce(v.content_id, e.content_id) as content_id,
      coalesce(v.views, 0)::bigint as views,
      coalesce(e.engagement, 0)::bigint as engagement
    from item_views v
    full outer join item_engagement e
      on v.content_kind = e.content_kind and v.content_id = e.content_id
    where coalesce(v.views, 0) > 0 or coalesce(e.engagement, 0) > 0
  )
  select
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'content_kind', r.content_kind,
            'content_id', r.content_id::text,
            'views', r.views,
            'engagement', r.engagement
          )
          order by r.views desc, r.engagement desc
        )
        from (
          select * from combined_items
          order by views desc, engagement desc
          limit 20
        ) r
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'content_kind', r.content_kind,
            'content_id', r.content_id::text,
            'views', r.views,
            'engagement', r.engagement
          )
          order by r.engagement desc, r.views desc
        )
        from (
          select * from combined_items
          order by engagement desc, views desc
          limit 20
        ) r
      ),
      '[]'::jsonb
    )
  into j_top_views, j_top_engagement;

  j_top := coalesce(j_top_views, '[]'::jsonb);

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'days', v_days,
      'viewer_id', v_uid::text,
      'engagement_rate_denominator', 'content_views',
      'engagement_rate_definition',
        'total_engagement divided by content_views in period (excludes self; stories counted in content_views.story)'
    ),
    'data', jsonb_build_object(
      'coverage', jsonb_build_object(
        'profile_visits_since', v_profile_since,
        'content_views_since', v_content_since,
        'follower_events_since', v_follower_events_since,
        'shares_since', v_shares_since
      ),
      'period', jsonb_build_object(
        'start', v_start::text,
        'end', v_end::text,
        'prior_start', v_prior_start::text,
        'prior_end', v_prior_end::text
      ),
      'summary', jsonb_build_object(
        'profile_views', v_profile_views,
        'unique_visitors', v_unique_visitors,
        'content_views', v_content_views + v_story_views,
        'content_unique_viewers', v_content_unique,
        'new_followers', v_new_followers,
        'unfollows', v_unfollows,
        'net_followers', v_new_followers - v_unfollows,
        'likes', v_likes,
        'comments', v_comments,
        'saves', v_saves,
        'shares_initiated', v_shares_initiated,
        'shares_completed', v_shares_completed,
        'total_engagement', v_engagement,
        'engagement_rate', case
          when (v_content_views + v_story_views) > 0
            then round((v_engagement::numeric / (v_content_views + v_story_views)::numeric), 4)
          else null
        end
      ),
      'summary_prior', jsonb_build_object(
        'profile_views', v_profile_views_prior,
        'unique_visitors', v_unique_prior,
        'content_views', v_content_views_prior + v_story_views_prior,
        'new_followers', v_new_followers_prior,
        'unfollows', v_unfollows_prior,
        'net_followers', v_new_followers_prior - v_unfollows_prior,
        'total_engagement', v_engagement_prior
      ),
      'series', jsonb_build_object(
        'profile_views_per_day', j_profile_views,
        'unique_visitors_per_day', j_unique_visitors,
        'content_views_per_day', j_content_views,
        'follower_net_per_day', j_net_followers,
        'new_followers_per_day', j_new_followers_series,
        'unfollows_per_day', j_unfollows_series
      ),
      'content_views_by_kind', j_by_kind,
      'top_content', j_top,
      'top_content_by_views', coalesce(j_top_views, '[]'::jsonb),
      'top_content_by_engagement', coalesce(j_top_engagement, '[]'::jsonb)
    )
  );
end;
$$;

revoke all on function public.rpc_v1_profile_insights_bootstrap(integer, date, date) from public;
grant execute on function public.rpc_v1_profile_insights_bootstrap(integer, date, date) to authenticated;

comment on function public.rpc_v1_profile_insights_bootstrap(integer, date, date) is
  'Owner-only Profile Insights. Preset p_days (7–90) or custom inclusive UTC p_start..p_end; prior window matches length.';