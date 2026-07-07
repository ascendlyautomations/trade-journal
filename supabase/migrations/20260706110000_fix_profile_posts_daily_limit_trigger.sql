-- Fix: profile_posts trigger must not reference NEW.trade_id (column exists on posts only).
-- posts_enforce_free_plan_daily_limit() was incorrectly shared with profile_posts.

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
      using hint = 'Free plan allows only 3 posts per day';
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
      using hint = 'Free plan allows only 3 posts per day';
  end if;

  return new;
end;
$$;

drop trigger if exists profile_posts_enforce_free_plan_daily_limit on public.profile_posts;
create trigger profile_posts_enforce_free_plan_daily_limit
  before insert on public.profile_posts
  for each row
  execute function public.profile_posts_enforce_free_plan_daily_limit();
