-- Free plan messaging: unlimited Trade Room messages; 25 private DMs per rolling 24h.

create or replace function public.free_plan_count_direct_messages_rolling_24h(
  p_user_id uuid
)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.messages m
  where m.sender_id = p_user_id
    and m.conversation_id is not null
    and coalesce(m.is_system, false) = false
    and m.created_at >= now() - interval '24 hours';
$$;

comment on function public.free_plan_count_direct_messages_rolling_24h(uuid) is
  'Private direct messages sent by the user in the last 24 hours (rolling window).';

create or replace function public.rate_limit_messages_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  free_plan_daily_dm_limit constant integer := 25;
  dm_count integer;
begin
  if public.rate_limit_is_service_role() then
    return NEW;
  end if;

  if coalesce(NEW.is_system, false) then
    return NEW;
  end if;

  -- Participant/system rows without an explicit sender.
  if NEW.conversation_id is not null and NEW.sender_id is null then
    return NEW;
  end if;

  -- Only private conversation messages count toward the DM cap.
  if NEW.conversation_id is null or NEW.sender_id is null then
    return NEW;
  end if;

  if public.profile_is_pro_user(NEW.sender_id) then
    return NEW;
  end if;

  dm_count := public.free_plan_count_direct_messages_rolling_24h(NEW.sender_id);

  if coalesce(dm_count, 0) >= free_plan_daily_dm_limit then
    raise exception 'FREE_PLAN_DAILY_DM_LIMIT'
      using hint = 'You''ve reached the Free plan limit of 25 direct messages every 24 hours.';
  end if;

  return NEW;
end;
$$;

comment on function public.rate_limit_messages_before_insert() is
  'Free plan: 25 private DMs per rolling 24h. Pro/trialing users: unlimited.';

create or replace function public.rate_limit_room_messages_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Trade Room messages are unlimited for all plans.
  return NEW;
end;
$$;

comment on function public.rate_limit_room_messages_before_insert() is
  'Trade Room messages are unlimited (no free-plan cap).';

-- Retire production room_message caps; keep message_send rules for abuse monitoring on Pro only.
delete from public.rate_limit_rules
where action = 'room_message';

-- Free users are gated by FREE_PLAN_DAILY_DM_LIMIT; Pro users bypass message_send rules in trigger.
delete from public.rate_limit_rules
where action = 'message_send';
