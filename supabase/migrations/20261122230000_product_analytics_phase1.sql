-- Phase 1 — Product analytics (lightweight events + daily rollups). Does not alter admin_analytics_bundle.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.product_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  event_name text not null,
  platform text not null,
  session_id uuid not null,
  occurred_at timestamptz not null default timezone('utc', now()),
  origin text not null default 'user',
  dedupe_key text,
  props jsonb not null default '{}'::jsonb,
  constraint product_events_platform_check check (platform in ('web', 'ios')),
  constraint product_events_origin_check check (origin in ('user', 'server')),
  constraint product_events_props_object check (jsonb_typeof(props) = 'object')
);

create unique index if not exists product_events_user_dedupe_uidx
  on public.product_events (user_id, dedupe_key)
  where dedupe_key is not null;

create index if not exists product_events_occurred_at_idx
  on public.product_events (occurred_at desc);

create index if not exists product_events_user_day_idx
  on public.product_events (user_id, (timezone('utc', occurred_at)::date));

create index if not exists product_events_name_day_idx
  on public.product_events (event_name, (timezone('utc', occurred_at)::date));

comment on table public.product_events is
  'Append-only product analytics events (engagement). Raw retention ~90 days; rollups retained longer.';

create table if not exists public.product_daily_user_activity (
  user_id uuid not null references public.profiles (id) on delete cascade,
  activity_day date not null,
  session_count integer not null default 0,
  app_open_count integer not null default 0,
  screen_view_count integer not null default 0,
  engaged boolean not null default false,
  platforms text[] not null default '{}'::text[],
  first_active_at timestamptz not null,
  last_active_at timestamptz not null,
  primary key (user_id, activity_day)
);

create index if not exists product_daily_user_activity_day_idx
  on public.product_daily_user_activity (activity_day desc);

comment on table public.product_daily_user_activity is
  'UTC-day engagement rollups per user (sessions, opens). Used for DAU/WAU/MAU and retention.';

create table if not exists public.product_user_engagement_summary (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  last_active_at timestamptz not null,
  last_session_at timestamptz,
  total_sessions bigint not null default 0,
  updated_at timestamptz not null default timezone('utc', now())
);

comment on table public.product_user_engagement_summary is
  'Per-user last active + lifetime session count (user-initiated only).';

create table if not exists public.product_daily_profile_views (
  viewed_profile_id uuid not null references public.profiles (id) on delete cascade,
  activity_day date not null,
  view_count integer not null default 0,
  unique_viewer_count integer not null default 0,
  primary key (viewed_profile_id, activity_day)
);

create index if not exists product_daily_profile_views_day_idx
  on public.product_daily_profile_views (activity_day desc);

create table if not exists public.product_profile_view_uniques (
  viewed_profile_id uuid not null references public.profiles (id) on delete cascade,
  viewer_id uuid not null references public.profiles (id) on delete cascade,
  activity_day date not null,
  primary key (viewed_profile_id, viewer_id, activity_day)
);

create table if not exists public.product_daily_feature_usage (
  feature_key text not null,
  activity_day date not null,
  platform text not null,
  unique_users integer not null default 0,
  use_count integer not null default 0,
  primary key (feature_key, activity_day, platform),
  constraint product_daily_feature_usage_platform_check check (platform in ('web', 'ios'))
);

create table if not exists public.product_daily_feature_user_day (
  feature_key text not null,
  activity_day date not null,
  platform text not null,
  user_id uuid not null references public.profiles (id) on delete cascade,
  primary key (feature_key, activity_day, platform, user_id)
);

alter table public.profiles
  add column if not exists last_product_active_at timestamptz;

comment on column public.profiles.last_product_active_at is
  'Last user-initiated product engagement (app open / session), not broker sync.';

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.product_events enable row level security;
alter table public.product_daily_user_activity enable row level security;
alter table public.product_user_engagement_summary enable row level security;
alter table public.product_daily_profile_views enable row level security;
alter table public.product_profile_view_uniques enable row level security;
alter table public.product_daily_feature_usage enable row level security;
alter table public.product_daily_feature_user_day enable row level security;

drop policy if exists product_events_insert_own on public.product_events;
create policy product_events_insert_own
  on public.product_events for insert to authenticated
  with check (
    user_id = auth.uid()
    and origin = 'user'
  );

-- Rollups: admin read only (reporting RPCs later). No client read/write.
drop policy if exists product_rollups_admin_select_daily_user on public.product_daily_user_activity;
create policy product_rollups_admin_select_daily_user
  on public.product_daily_user_activity for select to authenticated
  using (
    exists (select 1 from public.admin_users au where au.user_id = auth.uid())
  );

drop policy if exists product_rollups_admin_select_summary on public.product_user_engagement_summary;
create policy product_rollups_admin_select_summary
  on public.product_user_engagement_summary for select to authenticated
  using (
    exists (select 1 from public.admin_users au where au.user_id = auth.uid())
  );

drop policy if exists product_rollups_admin_select_profile_views on public.product_daily_profile_views;
create policy product_rollups_admin_select_profile_views
  on public.product_daily_profile_views for select to authenticated
  using (
    exists (select 1 from public.admin_users au where au.user_id = auth.uid())
  );

drop policy if exists product_rollups_admin_select_feature on public.product_daily_feature_usage;
create policy product_rollups_admin_select_feature
  on public.product_daily_feature_usage for select to authenticated
  using (
    exists (select 1 from public.admin_users au where au.user_id = auth.uid())
  );

-- Internal tables: no policies (service role + security definer functions only)

-- ---------------------------------------------------------------------------
-- Validation helpers
-- ---------------------------------------------------------------------------

create or replace function public.product_analytics_allowed_event_names()
returns text[]
language sql
immutable
as $$
  select array[
    'session_started',
    'app_opened',
    'screen_viewed',
    'profile_viewed',
    'feature_used',
    'milestone_onboarding_completed',
    'milestone_first_trade'
  ]::text[];
$$;

create or replace function public.product_analytics_sanitize_props(p_props jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_allowed text[] := array[
    'screen_id', 'profile_id', 'feature', 'signup_flow_source'
  ];
  v_key text;
  v_out jsonb := '{}'::jsonb;
  v_val text;
begin
  if p_props is null or p_props = 'null'::jsonb then
    return '{}'::jsonb;
  end if;
  if jsonb_typeof(p_props) <> 'object' then
    return '{}'::jsonb;
  end if;
  foreach v_key in array v_allowed loop
    if p_props ? v_key then
      v_val := left(trim(both '"' from (p_props ->> v_key)), 128);
      if v_val is not null and v_val <> '' then
        v_out := v_out || jsonb_build_object(v_key, v_val);
      end if;
    end if;
  end loop;
  return v_out;
end;
$$;

-- ---------------------------------------------------------------------------
-- Rollup application (per inserted event)
-- ---------------------------------------------------------------------------

create or replace function public.product_analytics_apply_event_rollup(
  p_user_id uuid,
  p_event_name text,
  p_platform text,
  p_occurred_at timestamptz,
  p_props jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := (timezone('utc', p_occurred_at))::date;
  v_feature text := nullif(trim(p_props ->> 'feature'), '');
  v_profile uuid := nullif(trim(p_props ->> 'profile_id'), '')::uuid;
  v_new_feature_user boolean;
begin
  insert into public.product_daily_user_activity (
    user_id,
    activity_day,
    session_count,
    app_open_count,
    screen_view_count,
    engaged,
    platforms,
    first_active_at,
    last_active_at
  )
  values (
    p_user_id,
    v_day,
    case when p_event_name = 'session_started' then 1 else 0 end,
    case when p_event_name = 'app_opened' then 1 else 0 end,
    case when p_event_name = 'screen_viewed' then 1 else 0 end,
    p_event_name in ('session_started', 'app_opened'),
  case when p_event_name in ('session_started', 'app_opened') then array[p_platform] else '{}'::text[] end,
    p_occurred_at,
    p_occurred_at
  )
  on conflict (user_id, activity_day) do update set
    session_count = product_daily_user_activity.session_count
      + case when p_event_name = 'session_started' then 1 else 0 end,
    app_open_count = product_daily_user_activity.app_open_count
      + case when p_event_name = 'app_opened' then 1 else 0 end,
    screen_view_count = product_daily_user_activity.screen_view_count
      + case when p_event_name = 'screen_viewed' then 1 else 0 end,
    engaged = product_daily_user_activity.engaged
      or p_event_name in ('session_started', 'app_opened'),
    platforms = (
      select array(select distinct unnest(
        product_daily_user_activity.platforms || case
          when p_event_name in ('session_started', 'app_opened', 'feature_used', 'screen_viewed')
          then array[p_platform] else '{}'::text[]
        end
      ))
    ),
    first_active_at = least(product_daily_user_activity.first_active_at, excluded.first_active_at),
    last_active_at = greatest(product_daily_user_activity.last_active_at, excluded.last_active_at);

  if p_event_name in ('session_started', 'app_opened', 'screen_viewed', 'feature_used', 'profile_viewed') then
    insert into public.product_user_engagement_summary (
      user_id,
      last_active_at,
      last_session_at,
      total_sessions,
      updated_at
    )
    values (
      p_user_id,
      p_occurred_at,
      case when p_event_name = 'session_started' then p_occurred_at else null end,
      case when p_event_name = 'session_started' then 1 else 0 end,
      timezone('utc', now())
    )
    on conflict (user_id) do update set
      last_active_at = greatest(product_user_engagement_summary.last_active_at, excluded.last_active_at),
      last_session_at = case
        when p_event_name = 'session_started' then greatest(
          coalesce(product_user_engagement_summary.last_session_at, excluded.last_session_at),
          excluded.last_session_at
        )
        else product_user_engagement_summary.last_session_at
      end,
      total_sessions = product_user_engagement_summary.total_sessions
        + case when p_event_name = 'session_started' then 1 else 0 end,
      updated_at = timezone('utc', now());

    update public.profiles
    set last_product_active_at = greatest(
      coalesce(last_product_active_at, p_occurred_at),
      p_occurred_at
    )
    where id = p_user_id;
  end if;

  if p_event_name = 'profile_viewed' and v_profile is not null and v_profile <> p_user_id then
    insert into public.product_daily_profile_views (
      viewed_profile_id,
      activity_day,
      view_count,
      unique_viewer_count
    )
    values (v_profile, v_day, 1, 0)
    on conflict (viewed_profile_id, activity_day) do update set
      view_count = product_daily_profile_views.view_count + 1;

    insert into public.product_profile_view_uniques (viewed_profile_id, viewer_id, activity_day)
    values (v_profile, p_user_id, v_day)
    on conflict do nothing;

    update public.product_daily_profile_views pv
    set unique_viewer_count = (
      select count(*)::int from public.product_profile_view_uniques u
      where u.viewed_profile_id = pv.viewed_profile_id and u.activity_day = pv.activity_day
    )
  where pv.viewed_profile_id = v_profile and pv.activity_day = v_day;
  end if;

  if p_event_name = 'feature_used' and v_feature is not null and length(v_feature) <= 64 then
    insert into public.product_daily_feature_user_day (
      feature_key, activity_day, platform, user_id
    )
    values (v_feature, v_day, p_platform, p_user_id)
    on conflict do nothing;

    v_new_feature_user := found;

    insert into public.product_daily_feature_usage (
      feature_key, activity_day, platform, unique_users, use_count
    )
    values (
      v_feature,
      v_day,
      p_platform,
      case when coalesce(v_new_feature_user, false) then 1 else 0 end,
      1
    )
    on conflict (feature_key, activity_day, platform) do update set
      use_count = product_daily_feature_usage.use_count + 1,
      unique_users = (
        select count(*)::int from public.product_daily_feature_user_day f
        where f.feature_key = excluded.feature_key
          and f.activity_day = excluded.activity_day
          and f.platform = excluded.platform
      );
  end if;
end;
$$;

revoke all on function public.product_analytics_apply_event_rollup(uuid, text, text, timestamptz, jsonb) from public;

-- ---------------------------------------------------------------------------
-- Client batch ingest
-- ---------------------------------------------------------------------------

create or replace function public.rpc_v1_product_events_ingest(p_batch jsonb)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_allowed text[] := public.product_analytics_allowed_event_names();
  v_item jsonb;
  v_name text;
  v_platform text;
  v_session uuid;
  v_dedupe text;
  v_props jsonb;
  v_at timestamptz;
  v_inserted int := 0;
  v_skipped int := 0;
  v_max int := 25;
  v_i int := 0;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_batch is null or jsonb_typeof(p_batch) <> 'array' then
    return jsonb_build_object('inserted', 0, 'skipped', 0);
  end if;
  if jsonb_array_length(p_batch) > v_max then
    raise exception 'batch too large (max %)', v_max using errcode = '22023';
  end if;

  for v_item in select value from jsonb_array_elements(p_batch) loop
    v_i := v_i + 1;
    v_name := lower(trim(v_item ->> 'event_name'));
    if v_name is null or not (v_name = any (v_allowed)) then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    v_platform := lower(trim(v_item ->> 'platform'));
    if v_platform not in ('web', 'ios') then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    begin
      v_session := (v_item ->> 'session_id')::uuid;
    exception when others then
      v_skipped := v_skipped + 1;
      continue;
    end;
    if v_session is null then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    v_dedupe := nullif(left(trim(v_item ->> 'dedupe_key'), 256), '');
    v_props := public.product_analytics_sanitize_props(v_item -> 'props');
    v_at := timezone('utc', now());
    if v_item ? 'occurred_at' then
      begin
        v_at := (v_item ->> 'occurred_at')::timestamptz;
      exception when others then
        v_at := timezone('utc', now());
      end;
    end if;

    begin
      insert into public.product_events (
        user_id,
        event_name,
        platform,
        session_id,
        occurred_at,
        origin,
        dedupe_key,
        props
      )
      values (
        v_uid,
        v_name,
        v_platform,
        v_session,
        v_at,
        'user',
        v_dedupe,
        v_props
      );
      perform public.product_analytics_apply_event_rollup(
        v_uid, v_name, v_platform, v_at, v_props
      );
      v_inserted := v_inserted + 1;
    exception
      when unique_violation then
        v_skipped := v_skipped + 1;
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'skipped', v_skipped);
end;
$$;

revoke all on function public.rpc_v1_product_events_ingest(jsonb) from public;
grant execute on function public.rpc_v1_product_events_ingest(jsonb) to authenticated;

comment on function public.rpc_v1_product_events_ingest(jsonb) is
  'Authenticated batch ingest for product analytics (max 25). Idempotent via dedupe_key.';

-- ---------------------------------------------------------------------------
-- Server milestones (onboarding + first user-attributed trade)
-- ---------------------------------------------------------------------------

create or replace function public.product_analytics_emit_server_event(
  p_user_id uuid,
  p_event_name text,
  p_platform text,
  p_dedupe_key text,
  p_props jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session uuid := gen_random_uuid();
  v_at timestamptz := timezone('utc', now());
  v_props jsonb := public.product_analytics_sanitize_props(p_props);
begin
  if p_user_id is null or p_dedupe_key is null then
    return;
  end if;
  if p_event_name <> all (public.product_analytics_allowed_event_names()) then
    return;
  end if;
  if p_platform not in ('web', 'ios', 'server') then
    p_platform := 'web';
  end if;
  begin
    insert into public.product_events (
      user_id,
      event_name,
      platform,
      session_id,
      occurred_at,
      origin,
      dedupe_key,
      props
    )
    values (
      p_user_id,
      p_event_name,
      case when p_platform = 'server' then 'web' else p_platform end,
      v_session,
      v_at,
      'server',
      p_dedupe_key,
      v_props
    );
    perform public.product_analytics_apply_event_rollup(
      p_user_id,
      p_event_name,
      case when p_platform = 'server' then 'web' else p_platform end,
      v_at,
      v_props
    );
  exception
    when unique_violation then
      null;
  end;
end;
$$;

revoke all on function public.product_analytics_emit_server_event(uuid, text, text, text, jsonb) from public;

create or replace function public.product_analytics_onboarding_milestone()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE'
     and coalesce(old.onboarding_completed, false) = false
     and coalesce(new.onboarding_completed, false) = true
  then
    perform public.product_analytics_emit_server_event(
      new.id,
      'milestone_onboarding_completed',
      'server',
      'milestone:onboarding:' || new.id::text,
      '{}'::jsonb
    );
  end if;
  return new;
end;
$$;

drop trigger if exists product_analytics_profiles_onboarding_milestone on public.profiles;
create trigger product_analytics_profiles_onboarding_milestone
  after update of onboarding_completed on public.profiles
  for each row
  execute function public.product_analytics_onboarding_milestone();

create or replace function public.product_analytics_first_trade_milestone()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count bigint;
  v_src text := lower(coalesce(trim(new.import_source), 'manual'));
begin
  if new.user_id is null then
    return new;
  end if;
  -- Skip bulk broker initial imports — not user engagement.
  if coalesce(new.is_initial_import, false) = true
     and v_src in ('tradovate', 'rithmic')
  then
    return new;
  end if;
  select count(*) into v_count
  from public.trades t
  where t.user_id = new.user_id
    and t.id <> new.id;
  if v_count > 0 then
    return new;
  end if;
  perform public.product_analytics_emit_server_event(
    new.user_id,
    'milestone_first_trade',
    'server',
    'milestone:first_trade:' || new.user_id::text,
    jsonb_build_object('feature', coalesce(nullif(v_src, ''), 'manual'))
  );
  return new;
end;
$$;

drop trigger if exists product_analytics_trades_first_trade_milestone on public.trades;
create trigger product_analytics_trades_first_trade_milestone
  after insert on public.trades
  for each row
  execute function public.product_analytics_first_trade_milestone();

-- ---------------------------------------------------------------------------
-- Retention purge (raw events)
-- ---------------------------------------------------------------------------

create or replace function public.product_analytics_purge_raw_events(p_keep_days int default 90)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cutoff timestamptz := timezone('utc', now()) - make_interval(days => greatest(p_keep_days, 30));
  v_deleted bigint;
begin
  delete from public.product_events where occurred_at < v_cutoff;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.product_analytics_purge_raw_events(int) from public;

-- Schedule weekly purge when pg_cron is available (no-op if unconfigured).
do $cron$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'product_analytics_purge_raw_events';
    perform cron.schedule(
      'product_analytics_purge_raw_events',
      '15 6 * * 0',
      $job$select public.product_analytics_purge_raw_events(90);$job$
    );
  end if;
exception
  when others then
    raise notice 'product_analytics purge cron not scheduled: %', sqlerrm;
end;
$cron$;