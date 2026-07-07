-- Free plan: up to 3 manual trades and 3 posts per UTC calendar day (Pro unlimited).

create or replace function public.profile_is_pro_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(p.is_pro, false)
    or lower(trim(coalesce(p.subscription_status::text, ''))) in ('active', 'trialing')
  from public.profiles p
  where p.id = p_user_id;
$$;

comment on function public.profile_is_pro_user(uuid) is
  'True when the user has an active Pro or trialing subscription.';

create or replace function public.free_plan_utc_day_start()
returns timestamptz
language sql
stable
set search_path = public
as $$
  select date_trunc('day', now() at time zone 'utc') at time zone 'utc';
$$;

create or replace function public.free_plan_count_trades_today(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.trades t
  where t.user_id = p_user_id
    and t.created_at >= public.free_plan_utc_day_start()
    and t.created_at < public.free_plan_utc_day_start() + interval '1 day'
    and coalesce(t.mode, '') <> 'backtest'
    and lower(trim(coalesce(t.account_type::text, ''))) <> 'imported';
$$;

create or replace function public.free_plan_count_posts_today(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select (
    (
      select count(*)::integer
      from public.posts p
      where p.user_id = p_user_id
        and p.created_at >= public.free_plan_utc_day_start()
        and p.created_at < public.free_plan_utc_day_start() + interval '1 day'
    )
    +
    (
      select count(*)::integer
      from public.profile_posts pp
      where pp.user_id = p_user_id
        and pp.created_at >= public.free_plan_utc_day_start()
        and pp.created_at < public.free_plan_utc_day_start() + interval '1 day'
    )
  );
$$;

create or replace function public.trades_enforce_free_plan_daily_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  free_plan_daily_trade_limit constant integer := 3;
  trade_count integer;
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if coalesce(new.mode, '') = 'backtest' then
    return new;
  end if;

  if lower(trim(coalesce(new.account_type::text, ''))) = 'imported' then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  trade_count := public.free_plan_count_trades_today(new.user_id);

  if coalesce(trade_count, 0) >= free_plan_daily_trade_limit then
    raise exception 'FREE_PLAN_DAILY_TRADE_LIMIT'
      using hint = 'Free plan allows only 3 trades per day';
  end if;

  return new;
end;
$$;

create or replace function public.posts_enforce_free_plan_daily_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  free_plan_daily_post_limit constant integer := 3;
  post_count integer;
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  -- Trade feed upsert: re-publishing an existing trade post does not count again.
  if new.trade_id is not null
     and exists (
       select 1
       from public.posts p
       where p.trade_id = new.trade_id
     ) then
    return new;
  end if;

  post_count := public.free_plan_count_posts_today(new.user_id);

  if coalesce(post_count, 0) >= free_plan_daily_post_limit then
    raise exception 'FREE_PLAN_DAILY_POST_LIMIT'
      using hint = 'Free plan allows only 3 posts per day';
  end if;

  return new;
end;
$$;

comment on function public.posts_enforce_free_plan_daily_limit() is
  'Free plan daily post cap for public.posts (trade feed posts with trade_id).';

create or replace function public.profile_posts_enforce_free_plan_daily_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  free_plan_daily_post_limit constant integer := 3;
  post_count integer;
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  post_count := public.free_plan_count_posts_today(new.user_id);

  if coalesce(post_count, 0) >= free_plan_daily_post_limit then
    raise exception 'FREE_PLAN_DAILY_POST_LIMIT'
      using hint = 'Free plan allows only 3 posts per day';
  end if;

  return new;
end;
$$;

comment on function public.profile_posts_enforce_free_plan_daily_limit() is
  'Free plan daily post cap for public.profile_posts (profile wall posts).';

drop trigger if exists trades_enforce_free_plan_daily_limit on public.trades;
create trigger trades_enforce_free_plan_daily_limit
  before insert on public.trades
  for each row
  execute function public.trades_enforce_free_plan_daily_limit();

drop trigger if exists posts_enforce_free_plan_daily_limit on public.posts;
create trigger posts_enforce_free_plan_daily_limit
  before insert on public.posts
  for each row
  execute function public.posts_enforce_free_plan_daily_limit();

drop trigger if exists profile_posts_enforce_free_plan_daily_limit on public.profile_posts;
create trigger profile_posts_enforce_free_plan_daily_limit
  before insert on public.profile_posts
  for each row
  execute function public.profile_posts_enforce_free_plan_daily_limit();
