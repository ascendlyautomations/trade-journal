-- TraxPro / Free plan v2: unlimited manual trades, posts, DMs, CSV; 4 Clips/UTC day; Copy Trading Pro-only (when enforcement on).

-- ---------------------------------------------------------------------------
-- Retire Free daily trade and post subscription caps (abuse limits unchanged elsewhere).
-- ---------------------------------------------------------------------------

drop trigger if exists trades_enforce_free_plan_daily_limit on public.trades;
drop trigger if exists posts_enforce_free_plan_daily_limit on public.posts;
drop trigger if exists profile_posts_enforce_free_plan_daily_limit on public.profile_posts;

create or replace function public.trades_enforce_free_plan_daily_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  return new;
end;
$$;

comment on function public.trades_enforce_free_plan_daily_limit() is
  'Retired: Free plan no longer caps manual trades per day. Trigger dropped.';

create or replace function public.posts_enforce_free_plan_daily_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  return new;
end;
$$;

create or replace function public.profile_posts_enforce_free_plan_daily_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Free Clips: 4 per UTC calendar day (reels table — internal name unchanged).
-- ---------------------------------------------------------------------------

create or replace function public.reels_enforce_free_plan_daily_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  free_plan_daily_clip_limit constant integer := 4;
  clip_count integer;
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if not public.free_plan_limits_enforced() then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  perform pg_advisory_xact_lock(
    872343,
    hashtext(new.user_id::text || ':free_plan_clips')
  );

  clip_count := public.free_plan_count_clips_today(new.user_id);

  if coalesce(clip_count, 0) >= free_plan_daily_clip_limit then
    raise exception 'FREE_PLAN_DAILY_CLIP_LIMIT'
      using hint = 'You''ve reached the Free plan limit of 4 Clips per UTC calendar day.';
  end if;

  return new;
end;
$$;

comment on function public.reels_enforce_free_plan_daily_limit() is
  'Free plan: up to 4 Clips (reels rows) per UTC calendar day when entitlement enforcement is on.';

-- ---------------------------------------------------------------------------
-- Direct messages: remove Free subscription cap; keep abuse rate limits.
-- ---------------------------------------------------------------------------

create or replace function public.rate_limit_messages_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if coalesce(new.is_system, false) then
    return new;
  end if;

  if new.conversation_id is not null and new.sender_id is null then
    return new;
  end if;

  if new.sender_id is null then
    return new;
  end if;

  perform public.rate_limit_hit('message_send');

  return new;
end;
$$;

comment on function public.rate_limit_messages_before_insert() is
  'DM abuse limits for all plans. Free plan no longer has a 25/24h subscription cap.';

-- ---------------------------------------------------------------------------
-- Copy Trading: require TraxPro when global entitlement enforcement is on.
-- ---------------------------------------------------------------------------

create or replace function public.copy_trading_groups_enforce_traxpro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if not public.free_plan_limits_enforced() then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  raise exception 'TRAXPRO_COPY_TRADING_REQUIRED'
    using hint = 'Copy Trading is available with TraxPro.';
end;
$$;

drop trigger if exists copy_trading_groups_enforce_traxpro on public.copy_trading_groups;
create trigger copy_trading_groups_enforce_traxpro
  before insert on public.copy_trading_groups
  for each row
  execute function public.copy_trading_groups_enforce_traxpro();

create or replace function public.trades_enforce_copy_trading_traxpro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if new.copy_trading_group_id is null then
    return new;
  end if;

  if not public.free_plan_limits_enforced() then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  -- Free: block newly linking a trade to a copy group, not edits to already-linked rows.
  if tg_op = 'UPDATE' then
    if old.copy_trading_group_id is not distinct from new.copy_trading_group_id then
      return new;
    end if;
    if old.copy_trading_group_id is not null and new.copy_trading_group_id is null then
      return new;
    end if;
  end if;

  raise exception 'TRAXPRO_COPY_TRADING_REQUIRED'
    using hint = 'Copy Trading is available with TraxPro.';
end;
$$;

drop trigger if exists trades_enforce_copy_trading_traxpro on public.trades;
create trigger trades_enforce_copy_trading_traxpro
  before insert or update of copy_trading_group_id on public.trades
  for each row
  execute function public.trades_enforce_copy_trading_traxpro();

comment on function public.copy_trading_groups_enforce_traxpro() is
  'Blocks new copy trading groups for Free users when entitlement_enforcement_enabled is true.';

comment on function public.trades_enforce_copy_trading_traxpro() is
  'Blocks new copy-group links (INSERT or copy_trading_group_id change) for Free users when enforcement is on. Preserves edits to already-linked trades.';
