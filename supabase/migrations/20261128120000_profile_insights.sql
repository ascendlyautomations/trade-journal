-- Profile Insights: creator rollups, follower events, shares, owner bootstrap RPC.
--
-- Deployment order (do not skip):
--   1. 20261122230000_product_analytics_phase1.sql (product_daily_profile_views + profile_viewed ingest)
--   2. 20261126001500_feed_content_impressions.sql (+ later feed bootstrap migrations if used)
--   3. This file (20261128120000_profile_insights.sql)
--   4. If step 3 was applied before bootstrap fixes: 20261128140000_profile_insights_bootstrap_fixes.sql
--   5. Ship clients that call rpc_v1_feed_record_impressions / rpc_v1_creator_record_shares and
--      rpc_v1_profile_insights_bootstrap after the RPC exists.
--
-- Depends: product analytics phase 1, feed_content_impressions, story_views, engagement tables.

-- =============================================================================
-- Tables
-- =============================================================================

create table if not exists public.creator_content_view_uniques (
  creator_id uuid not null references public.profiles (id) on delete cascade,
  viewer_id uuid not null references public.profiles (id) on delete cascade,
  content_kind text not null,
  content_id uuid not null,
  activity_day date not null,
  primary key (creator_id, viewer_id, content_kind, content_id, activity_day),
  constraint creator_content_view_uniques_kind_check check (
    content_kind in ('post', 'profile_post', 'achievement_post', 'reel')
  )
);

create table if not exists public.creator_content_views_daily (
  creator_id uuid not null references public.profiles (id) on delete cascade,
  activity_day date not null,
  content_kind text not null,
  view_count integer not null default 0,
  unique_viewer_count integer not null default 0,
  primary key (creator_id, activity_day, content_kind),
  constraint creator_content_views_daily_kind_check check (
    content_kind in ('post', 'profile_post', 'achievement_post', 'reel')
  )
);

create table if not exists public.creator_content_item_daily (
  creator_id uuid not null references public.profiles (id) on delete cascade,
  content_kind text not null,
  content_id uuid not null,
  activity_day date not null,
  view_count integer not null default 0,
  unique_viewer_count integer not null default 0,
  primary key (creator_id, content_kind, content_id, activity_day),
  constraint creator_content_item_daily_kind_check check (
    content_kind in ('post', 'profile_post', 'achievement_post', 'reel')
  )
);

create index if not exists creator_content_views_daily_creator_day_idx
  on public.creator_content_views_daily (creator_id, activity_day desc);

create table if not exists public.creator_follower_events (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles (id) on delete cascade,
  follower_id uuid not null references public.profiles (id) on delete cascade,
  event_type text not null,
  occurred_at timestamptz not null default timezone('utc', now()),
  constraint creator_follower_events_type_check check (event_type in ('follow', 'unfollow'))
);

create index if not exists creator_follower_events_creator_time_idx
  on public.creator_follower_events (creator_id, occurred_at desc);

create table if not exists public.creator_share_events (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles (id) on delete cascade,
  content_kind text not null,
  content_id uuid not null,
  sharer_id uuid not null references public.profiles (id) on delete cascade,
  share_phase text not null,
  platform text not null default 'ios',
  occurred_at timestamptz not null default timezone('utc', now()),
  constraint creator_share_events_kind_check check (
    content_kind in ('post', 'profile_post', 'achievement_post', 'reel', 'trader_profile')
  ),
  constraint creator_share_events_phase_check check (share_phase in ('initiated', 'completed')),
  constraint creator_share_events_platform_check check (platform in ('web', 'ios'))
);

create index if not exists creator_share_events_creator_time_idx
  on public.creator_share_events (creator_id, occurred_at desc);

alter table public.creator_content_view_uniques enable row level security;
alter table public.creator_content_views_daily enable row level security;
alter table public.creator_content_item_daily enable row level security;
alter table public.creator_follower_events enable row level security;
alter table public.creator_share_events enable row level security;
-- No client policies: security definer RPCs + ingest functions only.

-- =============================================================================
-- Resolve content owner (excludes invalid ids)
-- =============================================================================

create or replace function public._creator_resolve_content_owner(p_kind text, p_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select case lower(trim(p_kind))
    when 'post' then (select p.user_id from public.posts p where p.id = p_id)
    when 'profile_post' then (select pp.user_id from public.profile_posts pp where pp.id = p_id)
    when 'achievement_post' then (select ap.user_id from public.achievement_posts ap where ap.id = p_id)
    when 'reel' then (select r.user_id from public.reels r where r.id = p_id)
    else null::uuid
  end;
$$;

revoke all on function public._creator_resolve_content_owner(text, uuid) from public;

-- =============================================================================
-- Creator view rollup (30s debounce aligned with feed impressions)
-- =============================================================================

create or replace function public._creator_apply_content_view(
  p_viewer_id uuid,
  p_kind text,
  p_content_id uuid,
  p_surface text default 'feed'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_creator uuid;
  v_day date := (timezone('utc', now()))::date;
  v_kind text := lower(trim(p_kind));
  v_new_unique boolean := false;
begin
  if p_viewer_id is null or p_content_id is null then
    return false;
  end if;
  v_creator := public._creator_resolve_content_owner(v_kind, p_content_id);
  if v_creator is null or v_creator = p_viewer_id then
    return false;
  end if;

  insert into public.creator_content_view_uniques (
    creator_id, viewer_id, content_kind, content_id, activity_day
  )
  values (v_creator, p_viewer_id, v_kind, p_content_id, v_day)
  on conflict do nothing;
  v_new_unique := found;

  insert into public.creator_content_views_daily (
    creator_id, activity_day, content_kind, view_count, unique_viewer_count
  )
  values (
    v_creator, v_day, v_kind,
    1,
    case when v_new_unique then 1 else 0 end
  )
  on conflict (creator_id, activity_day, content_kind) do update set
    view_count = creator_content_views_daily.view_count + 1,
    unique_viewer_count = creator_content_views_daily.unique_viewer_count
      + case when v_new_unique then 1 else 0 end;

  insert into public.creator_content_item_daily (
    creator_id, content_kind, content_id, activity_day, view_count, unique_viewer_count
  )
  values (
    v_creator, v_kind, p_content_id, v_day, 1,
    case when v_new_unique then 1 else 0 end
  )
  on conflict (creator_id, content_kind, content_id, activity_day) do update set
    view_count = creator_content_item_daily.view_count + 1,
    unique_viewer_count = creator_content_item_daily.unique_viewer_count
      + case when v_new_unique then 1 else 0 end;

  return true;
end;
$$;

revoke all on function public._creator_apply_content_view(uuid, text, uuid, text) from public;

-- =============================================================================
-- Patch feed impression ingest → creator rollups (ranking path unchanged)
-- =============================================================================

create or replace function public.rpc_v1_feed_record_impressions(p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_item jsonb;
  v_kind text;
  v_id uuid;
  v_surface text;
  v_count integer := 0;
  v_creator_count integer := 0;
  v_max integer := 50;
  v_applied boolean;
  v_upserted integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'invalid_items' using errcode = '22023';
  end if;

  if jsonb_array_length(p_items) > v_max then
    raise exception 'batch_too_large' using errcode = '22023';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_kind := lower(trim(coalesce(v_item ->> 'content_kind', v_item ->> 'kind', '')));
    if v_kind not in ('post', 'profile_post', 'achievement_post', 'reel') then
      continue;
    end if;

    begin
      v_id := (v_item ->> 'content_id')::uuid;
    exception
      when others then
        continue;
    end;

    if v_id is null then
      continue;
    end if;

    if v_kind = 'post' and not exists (select 1 from public.posts p where p.id = v_id) then
      continue;
    elsif v_kind = 'profile_post' and not exists (select 1 from public.profile_posts pp where pp.id = v_id) then
      continue;
    elsif v_kind = 'achievement_post' and not exists (
      select 1 from public.achievement_posts ap where ap.id = v_id
    ) then
      continue;
    elsif v_kind = 'reel' and not exists (select 1 from public.reels r where r.id = v_id) then
      continue;
    end if;

    v_surface := nullif(trim(coalesce(v_item ->> 'surface', 'feed')), '');

    with upserted as (
      insert into public.feed_content_impressions (
        viewer_id, content_kind, content_id, first_impressed_at, last_impressed_at, impression_count
      )
      values (v_uid, v_kind, v_id, timezone('utc', now()), timezone('utc', now()), 1)
      on conflict (viewer_id, content_kind, content_id) do update
        set
          last_impressed_at = excluded.last_impressed_at,
          impression_count = feed_content_impressions.impression_count + 1
        where feed_content_impressions.last_impressed_at
              < timezone('utc', now()) - interval '30 seconds'
      returning 1
    )
    select coalesce((select count(*) from upserted), 0) into v_upserted;

    v_count := v_count + v_upserted;

    if v_upserted > 0 then
      v_applied := public._creator_apply_content_view(
        v_uid, v_kind, v_id, coalesce(v_surface, 'feed')
      );
      if v_applied then
        v_creator_count := v_creator_count + 1;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'recorded', v_count,
    'creator_recorded', v_creator_count,
    'accepted', jsonb_array_length(p_items)
  );
end;
$$;

-- =============================================================================
-- Content views from Profile / Detail (same debounce via feed impression row)
-- =============================================================================

create or replace function public.rpc_v1_creator_record_content_views(p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
begin
  return public.rpc_v1_feed_record_impressions(p_items);
end;
$$;

grant execute on function public.rpc_v1_creator_record_content_views(jsonb) to authenticated;

-- =============================================================================
-- Share events
-- =============================================================================

create or replace function public.rpc_v1_creator_record_shares(p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_item jsonb;
  v_kind text;
  v_id uuid;
  v_phase text;
  v_platform text;
  v_creator uuid;
  v_recorded int := 0;
  v_max int := 25;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    return jsonb_build_object('recorded', 0);
  end if;
  if jsonb_array_length(p_items) > v_max then
    raise exception 'batch_too_large' using errcode = '22023';
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_kind := lower(trim(coalesce(v_item ->> 'content_kind', '')));
    v_phase := lower(trim(coalesce(v_item ->> 'share_phase', 'initiated')));
    v_platform := lower(trim(coalesce(v_item ->> 'platform', 'ios')));
    if v_platform not in ('web', 'ios') then
      v_platform := 'ios';
    end if;
  if v_phase not in ('initiated', 'completed') then
      continue;
    end if;
    begin
      v_id := (v_item ->> 'content_id')::uuid;
    exception when others then
      continue;
    end;
    if v_id is null then
      continue;
    end if;

    if v_kind = 'trader_profile' then
      v_creator := v_id;
    else
      v_creator := public._creator_resolve_content_owner(v_kind, v_id);
    end if;
    if v_creator is null or v_creator = v_uid then
      continue;
    end if;

    insert into public.creator_share_events (
      creator_id, content_kind, content_id, sharer_id, share_phase, platform
    )
    values (v_creator, v_kind, v_id, v_uid, v_phase, v_platform);
    v_recorded := v_recorded + 1;
  end loop;

  return jsonb_build_object('recorded', v_recorded);
end;
$$;

grant execute on function public.rpc_v1_creator_record_shares(jsonb) to authenticated;

-- =============================================================================
-- Follower follow / unfollow event log
-- =============================================================================

create or replace function public.followers_creator_event_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.creator_follower_events (creator_id, follower_id, event_type)
    values (new.following_id, new.follower_id, 'follow');
    return new;
  elsif tg_op = 'DELETE' then
    insert into public.creator_follower_events (creator_id, follower_id, event_type)
    values (old.following_id, old.follower_id, 'unfollow');
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists followers_creator_event_log on public.followers;
create trigger followers_creator_event_log
  after insert or delete on public.followers
  for each row execute function public.followers_creator_event_log();

-- =============================================================================
-- Owner insights bootstrap
-- =============================================================================

create or replace function public.rpc_v1_profile_insights_bootstrap(p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_days integer := greatest(7, least(coalesce(p_days, 30), 90));
  v_end date := (timezone('utc', now()))::date;
  v_start date := v_end - (v_days - 1);
  v_prior_end date := v_start - 1;
  v_prior_start date := v_prior_end - (v_days - 1);
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

revoke all on function public.rpc_v1_profile_insights_bootstrap(integer) from public;
grant execute on function public.rpc_v1_profile_insights_bootstrap(integer) to authenticated;

comment on function public.rpc_v1_profile_insights_bootstrap(integer) is
  'Owner-only Profile Insights. Uses rollups + engagement tables; nullable coverage timestamps when history unavailable.';