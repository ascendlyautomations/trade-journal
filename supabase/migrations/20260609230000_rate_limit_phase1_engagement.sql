-- Phase 1: Postgres rate limiting — engagement tables (SHADOW MODE).
-- Prerequisite: messaging / room_messages / followers RLS migrations applied.
--
-- Scope:
--   messages, room_messages, comments, trade_comments, likes, trade_likes, followers
--
-- Shadow mode: seeded limits are intentionally very high so beta users are not blocked.
-- Tighten rate_limit_rules.max_count in a follow-up migration after monitoring.
--
-- Out of scope (later phases):
--   storage.objects, conversations, stories, support, profile_posts, ai_chat
--
-- Pre-flight:
--   select tablename from pg_tables
--   where schemaname = 'public'
--     and tablename in (
--       'messages', 'room_messages', 'comments', 'trade_comments',
--       'likes', 'trade_likes', 'followers'
--     )
--   order by 1;

-- =============================================================================
-- 1. Schema
-- =============================================================================

create table if not exists public.rate_limit_rules (
  action text not null,
  window_seconds integer not null,
  max_count integer not null,
  constraint rate_limit_rules_window_seconds_positive check (window_seconds > 0),
  constraint rate_limit_rules_max_count_positive check (max_count > 0),
  primary key (action, window_seconds)
);

comment on table public.rate_limit_rules is
  'Per-action fixed-window rate limits. Tuned via SQL; not client-writable.';

create table if not exists public.rate_limit_counters (
  user_id uuid not null,
  action text not null,
  window_seconds integer not null,
  window_start timestamptz not null,
  count integer not null default 0,
  constraint rate_limit_counters_count_non_negative check (count >= 0),
  primary key (user_id, action, window_seconds, window_start)
);

comment on table public.rate_limit_counters is
  'Mutable per-user counters; written only by rate_limit_hit().';

create index if not exists rate_limit_counters_window_start_idx
  on public.rate_limit_counters (window_start);

revoke all on table public.rate_limit_rules from anon, authenticated;
revoke all on table public.rate_limit_counters from anon, authenticated;

-- =============================================================================
-- 2. Core RPC
-- =============================================================================

create or replace function public.rate_limit_is_service_role()
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
    auth.jwt() ->> 'role',
    current_setting('request.jwt.claims', true)::json ->> 'role'
  ) = 'service_role';
$$;

comment on function public.rate_limit_is_service_role() is
  'True when the current JWT is service_role (bypass rate limits).';

create or replace function public.rate_limit_hit(p_action text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_rule record;
  v_window_start timestamptz;
  v_count integer;
begin
  if public.rate_limit_is_service_role() then
    return;
  end if;

  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'rate_limit_not_authenticated'
      using errcode = 'P0001';
  end if;

  if p_action is null or btrim(p_action) = '' then
    raise exception 'rate_limit_invalid_action'
      using errcode = 'P0001';
  end if;

  for v_rule in
    select r.window_seconds, r.max_count
    from public.rate_limit_rules r
    where r.action = p_action
    order by r.window_seconds
  loop
    v_window_start := to_timestamp(
      floor(extract(epoch from now()) / v_rule.window_seconds) * v_rule.window_seconds
    );

    insert into public.rate_limit_counters (
      user_id,
      action,
      window_seconds,
      window_start,
      count
    )
    values (
      v_user_id,
      p_action,
      v_rule.window_seconds,
      v_window_start,
      1
    )
    on conflict (user_id, action, window_seconds, window_start)
    do update
      set count = public.rate_limit_counters.count + 1
    returning public.rate_limit_counters.count into v_count;

    if v_count > v_rule.max_count then
      raise exception 'rate_limit_exceeded:%', p_action
        using errcode = 'P0001';
    end if;
  end loop;
end;
$$;

comment on function public.rate_limit_hit(text) is
  'Increment all windows for action/user; raise rate_limit_exceeded:{action} when over limit.';

revoke all on function public.rate_limit_hit(text) from public;
revoke all on function public.rate_limit_is_service_role() from public;

-- =============================================================================
-- 3. SHADOW MODE rules (extremely high — should not block normal beta usage)
-- =============================================================================
-- Production targets (for a later tighten migration):
--   message_send / room_message: 30/min, 500 or 300/day
--   comment:                   20/min, 100/day
--   like:                      60/min, 300/day
--   follow:                    30/hour, 200/day

insert into public.rate_limit_rules (action, window_seconds, max_count)
values
  ('message_send', 60, 10000),
  ('message_send', 3600, 50000),
  ('message_send', 86400, 100000),
  ('room_message', 60, 10000),
  ('room_message', 3600, 50000),
  ('room_message', 86400, 100000),
  ('comment', 60, 10000),
  ('comment', 3600, 50000),
  ('comment', 86400, 100000),
  ('like', 60, 10000),
  ('like', 3600, 50000),
  ('like', 86400, 100000),
  ('follow', 60, 10000),
  ('follow', 3600, 50000),
  ('follow', 86400, 100000)
on conflict (action, window_seconds) do update
  set max_count = excluded.max_count;

-- =============================================================================
-- 4. BEFORE INSERT trigger functions
-- =============================================================================

create or replace function public.rate_limit_messages_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return NEW;
  end if;

  -- System / participant-generated rows (e.g. "X added Y") — not user sends.
  if coalesce(NEW.is_system, false) then
    return NEW;
  end if;

  if NEW.conversation_id is not null and NEW.sender_id is null then
    return NEW;
  end if;

  perform public.rate_limit_hit('message_send');
  return NEW;
end;
$$;

create or replace function public.rate_limit_room_messages_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return NEW;
  end if;

  perform public.rate_limit_hit('room_message');
  return NEW;
end;
$$;

create or replace function public.rate_limit_comments_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return NEW;
  end if;

  perform public.rate_limit_hit('comment');
  return NEW;
end;
$$;

create or replace function public.rate_limit_trade_comments_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return NEW;
  end if;

  perform public.rate_limit_hit('comment');
  return NEW;
end;
$$;

create or replace function public.rate_limit_likes_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return NEW;
  end if;

  perform public.rate_limit_hit('like');
  return NEW;
end;
$$;

create or replace function public.rate_limit_trade_likes_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return NEW;
  end if;

  perform public.rate_limit_hit('like');
  return NEW;
end;
$$;

create or replace function public.rate_limit_followers_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return NEW;
  end if;

  perform public.rate_limit_hit('follow');
  return NEW;
end;
$$;

-- =============================================================================
-- 5. Attach triggers
-- =============================================================================

drop trigger if exists rate_limit_messages_before_insert on public.messages;
create trigger rate_limit_messages_before_insert
  before insert on public.messages
  for each row
  execute function public.rate_limit_messages_before_insert();

drop trigger if exists rate_limit_room_messages_before_insert on public.room_messages;
create trigger rate_limit_room_messages_before_insert
  before insert on public.room_messages
  for each row
  execute function public.rate_limit_room_messages_before_insert();

drop trigger if exists rate_limit_comments_before_insert on public.comments;
create trigger rate_limit_comments_before_insert
  before insert on public.comments
  for each row
  execute function public.rate_limit_comments_before_insert();

drop trigger if exists rate_limit_trade_comments_before_insert on public.trade_comments;
create trigger rate_limit_trade_comments_before_insert
  before insert on public.trade_comments
  for each row
  execute function public.rate_limit_trade_comments_before_insert();

drop trigger if exists rate_limit_likes_before_insert on public.likes;
create trigger rate_limit_likes_before_insert
  before insert on public.likes
  for each row
  execute function public.rate_limit_likes_before_insert();

drop trigger if exists rate_limit_trade_likes_before_insert on public.trade_likes;
create trigger rate_limit_trade_likes_before_insert
  before insert on public.trade_likes
  for each row
  execute function public.rate_limit_trade_likes_before_insert();

drop trigger if exists rate_limit_followers_before_insert on public.followers;
create trigger rate_limit_followers_before_insert
  before insert on public.followers
  for each row
  execute function public.rate_limit_followers_before_insert();

-- =============================================================================
-- ROLLBACK (manual)
-- =============================================================================
-- drop trigger if exists rate_limit_followers_before_insert on public.followers;
-- drop trigger if exists rate_limit_trade_likes_before_insert on public.trade_likes;
-- drop trigger if exists rate_limit_likes_before_insert on public.likes;
-- drop trigger if exists rate_limit_trade_comments_before_insert on public.trade_comments;
-- drop trigger if exists rate_limit_comments_before_insert on public.comments;
-- drop trigger if exists rate_limit_room_messages_before_insert on public.room_messages;
-- drop trigger if exists rate_limit_messages_before_insert on public.messages;
--
-- drop function if exists public.rate_limit_followers_before_insert();
-- drop function if exists public.rate_limit_trade_likes_before_insert();
-- drop function if exists public.rate_limit_likes_before_insert();
-- drop function if exists public.rate_limit_trade_comments_before_insert();
-- drop function if exists public.rate_limit_comments_before_insert();
-- drop function if exists public.rate_limit_room_messages_before_insert();
-- drop function if exists public.rate_limit_messages_before_insert();
--
-- drop function if exists public.rate_limit_hit(text);
-- drop function if exists public.rate_limit_is_service_role();
--
-- drop table if exists public.rate_limit_counters;
-- drop table if exists public.rate_limit_rules;
