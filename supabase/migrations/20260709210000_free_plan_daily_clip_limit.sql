-- Free plan: up to 3 clips (reels) per UTC calendar day (Pro unlimited).
-- Align trade/post limit hints with user-facing "every 24 hours" copy.

create or replace function public.free_plan_count_clips_today(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.reels r
  where r.user_id = p_user_id
    and r.created_at >= public.free_plan_utc_day_start()
    and r.created_at < public.free_plan_utc_day_start() + interval '1 day';
$$;

comment on function public.free_plan_count_clips_today(uuid) is
  'Clips (reels) created by the user since UTC midnight today.';

create or replace function public.reels_enforce_free_plan_daily_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  free_plan_daily_clip_limit constant integer := 3;
  clip_count integer;
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  clip_count := public.free_plan_count_clips_today(new.user_id);

  if coalesce(clip_count, 0) >= free_plan_daily_clip_limit then
    raise exception 'FREE_PLAN_DAILY_CLIP_LIMIT'
      using hint = 'You''ve reached the Free plan limit of 3 clips every 24 hours.';
  end if;

  return new;
end;
$$;

comment on function public.reels_enforce_free_plan_daily_limit() is
  'Free plan daily clip cap for public.reels.';

drop trigger if exists reels_enforce_free_plan_daily_limit on public.reels;
create trigger reels_enforce_free_plan_daily_limit
  before insert on public.reels
  for each row
  execute function public.reels_enforce_free_plan_daily_limit();

-- Refresh trade/post triggers so DB hints match canonical user-facing copy.
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
      using hint = 'You''ve reached the Free plan limit of 3 trades every 24 hours.';
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
      using hint = 'You''ve reached the Free plan limit of 3 posts every 24 hours.';
  end if;

  return new;
end;
$$;

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
      using hint = 'You''ve reached the Free plan limit of 3 posts every 24 hours.';
  end if;

  return new;
end;
$$;
