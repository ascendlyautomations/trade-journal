-- Transition-aware Free trade slots: epoch per downgrade, Pro restore for all accounts.

alter table public.profiles
  add column if not exists free_plan_trade_slots_epoch bigint not null default 0;

alter table public.profiles
  add column if not exists free_plan_trade_slots_confirmed_epoch bigint not null default 0;

comment on column public.profiles.free_plan_trade_slots_epoch is
  'Increments on each Pro→Free trade-slot downgrade; selection must match this generation.';

comment on column public.profiles.free_plan_trade_slots_confirmed_epoch is
  'Last free_plan_trade_slots_epoch the user confirmed via select_free_plan_trade_accounts.';

-- Explicit is_pro = false forces Free trade slots (supports admin/testing) even if Stripe still active.
create or replace function public.profile_trade_slots_pro(p public.profiles)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when p.is_pro = false then false
    when p.is_pro = true then true
    else public.profile_is_pro_user(p.id)
  end;
$$;

create or replace function public.profile_trade_slots_pro_for_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.profile_trade_slots_pro(p)
  from public.profiles p
  where p.id = p_user_id;
$$;

create or replace function public.free_plan_trade_slots_pending(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (
      select
        (select count(*)::int from public.accounts a where a.user_id = p_user_id)
        > 3
        and coalesce(p.free_plan_trade_slots_confirmed_epoch, 0)
          < coalesce(p.free_plan_trade_slots_epoch, 0)
      from public.profiles p
      where p.id = p_user_id
    ),
    false
  );
$$;

create or replace function public.apply_free_plan_trade_slot_downgrade(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_epoch bigint;
  v_account_count int;
begin
  if p_user_id is null then
    return;
  end if;

  update public.profiles
  set free_plan_trade_slots_epoch = coalesce(free_plan_trade_slots_epoch, 0) + 1
  where id = p_user_id
  returning free_plan_trade_slots_epoch into v_epoch;

  select count(*)::int into v_account_count
  from public.accounts
  where user_id = p_user_id;

  perform set_config('tradetraxs.mutate_can_add_trades', 'on', true);

  if coalesce(v_account_count, 0) <= 3 then
    update public.accounts
    set can_add_trades = true
    where user_id = p_user_id;

    update public.profiles
    set free_plan_trade_slots_confirmed_epoch = v_epoch
    where id = p_user_id;
  else
    update public.accounts
    set can_add_trades = false
    where user_id = p_user_id;
  end if;
end;
$$;

create or replace function public.restore_pro_trade_account_slots(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_epoch bigint;
begin
  if p_user_id is null then
    return;
  end if;

  if pg_trigger_depth() = 0
     and not public.rate_limit_is_service_role()
     and auth.uid() is distinct from p_user_id then
    raise exception 'NOT_AUTHORIZED';
  end if;

  select coalesce(free_plan_trade_slots_epoch, 0)
  into v_epoch
  from public.profiles
  where id = p_user_id;

  perform set_config('tradetraxs.mutate_can_add_trades', 'on', true);

  update public.accounts
  set can_add_trades = true
  where user_id = p_user_id;

  update public.profiles
  set free_plan_trade_slots_confirmed_epoch = coalesce(v_epoch, 0)
  where id = p_user_id;
end;
$$;

revoke all on function public.restore_pro_trade_account_slots(uuid) from public;
grant execute on function public.restore_pro_trade_account_slots(uuid) to authenticated;
grant execute on function public.restore_pro_trade_account_slots(uuid) to service_role;

create or replace function public.profiles_apply_trade_slot_entitlement_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  old_slots_pro boolean;
  new_slots_pro boolean;
begin
  old_slots_pro := public.profile_trade_slots_pro(old);
  new_slots_pro := public.profile_trade_slots_pro(new);

  if old_slots_pro is not distinct from new_slots_pro then
    return new;
  end if;

  if new_slots_pro then
    perform public.restore_pro_trade_account_slots(new.id);
  else
    perform public.apply_free_plan_trade_slot_downgrade(new.id);
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_apply_trade_slot_entitlement_change on public.profiles;
create trigger profiles_apply_trade_slot_entitlement_change
  after update of is_pro, creator_access, subscription_status, trial_end,
    early_access_status, early_access_campaign_id, early_access_enrollment_source,
    early_access_enrolled_at, early_access_started_at, early_access_ends_at
  on public.profiles
  for each row
  execute function public.profiles_apply_trade_slot_entitlement_change();

-- Trade writes: use trade-slot Pro (is_pro=false override) + epoch pending gate.
create or replace function public.trades_enforce_account_can_add_trades()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  acct_user uuid;
  acct_can_add boolean;
  uid uuid;
  acct_id text;
  slots_pro boolean;
begin
  if public.rate_limit_is_service_role() then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    uid := old.user_id;
    acct_id := nullif(trim(old.account_id::text), '');
  else
    uid := new.user_id;
    acct_id := nullif(trim(new.account_id::text), '');
  end if;

  if acct_id is null then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  select a.user_id, a.can_add_trades
  into acct_user, acct_can_add
  from public.accounts a
  where a.id::text = acct_id;

  if acct_user is null then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if acct_user is distinct from uid then
    raise exception 'ACCOUNT_OWNERSHIP_MISMATCH';
  end if;

  slots_pro := public.profile_trade_slots_pro_for_user(uid);

  if slots_pro then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if not public.free_plan_limits_enforced() then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if public.free_plan_trade_slots_pending(uid) then
    raise exception 'ACCOUNT_SLOT_SELECTION_REQUIRED';
  end if;

  if acct_can_add is not true then
    raise exception 'ACCOUNT_READ_ONLY';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.select_free_plan_trade_accounts(p_account_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  selected_count int;
  owned_count int;
  v_epoch bigint;
begin
  if uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  perform set_config('tradetraxs.mutate_can_add_trades', 'on', true);

  if public.profile_trade_slots_pro_for_user(uid) then
    perform public.restore_pro_trade_account_slots(uid);
    return;
  end if;

  select coalesce(free_plan_trade_slots_epoch, 0)
  into v_epoch
  from public.profiles
  where id = uid;

  selected_count := coalesce(cardinality(p_account_ids), 0);

  if selected_count > 3 then
    raise exception 'MUST_SELECT_AT_MOST_3';
  end if;

  if (
    select count(distinct x) from unnest(coalesce(p_account_ids, array[]::uuid[])) as t(x)
  ) <> selected_count then
    raise exception 'INVALID_ACCOUNT_SELECTION';
  end if;

  if selected_count > 0 then
    select count(*)::int into owned_count
    from public.accounts
    where user_id = uid
      and id = any (p_account_ids);

    if owned_count <> selected_count then
      raise exception 'INVALID_ACCOUNT_SELECTION';
    end if;
  end if;

  update public.accounts
  set can_add_trades = false
  where user_id = uid;

  if selected_count > 0 then
    update public.accounts
    set can_add_trades = true
    where user_id = uid
      and id = any (p_account_ids);
  end if;

  update public.profiles
  set free_plan_trade_slots_confirmed_epoch = v_epoch
  where id = uid;
end;
$$;

revoke all on function public.select_free_plan_trade_accounts(uuid[]) from public;
grant execute on function public.select_free_plan_trade_accounts(uuid[]) to authenticated;

create or replace function public.delete_own_trade(p_trade_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_owner uuid;
  v_account_id text;
  v_can_add boolean;
  v_post_ids uuid[];
  v_message_ids uuid[];
  v_reel record;
begin
  if p_trade_id is null then
    raise exception 'Trade id is required';
  end if;

  select user_id, nullif(trim(account_id::text), '')
  into v_owner, v_account_id
  from public.trades
  where id = p_trade_id;

  if v_owner is null then
    raise exception 'Trade not found';
  end if;

  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if v_owner is distinct from auth.uid() then
    raise exception 'Not authorized to delete this trade';
  end if;

  if v_account_id is not null
     and not public.profile_trade_slots_pro_for_user(v_owner)
     and public.free_plan_limits_enforced() then
    if public.free_plan_trade_slots_pending(v_owner) then
      raise exception 'ACCOUNT_SLOT_SELECTION_REQUIRED';
    end if;

    select a.can_add_trades
    into v_can_add
    from public.accounts a
    where a.id::text = v_account_id
      and a.user_id = v_owner;

    if found and v_can_add is not true then
      raise exception 'ACCOUNT_READ_ONLY';
    end if;
  end if;

  for v_reel in
    select id, video_url, thumbnail_url
    from public.reels
    where trade_id = p_trade_id
  loop
    delete from public.reel_likes where reel_id = v_reel.id;
    delete from public.reel_comments where reel_id = v_reel.id;
    delete from public.notifications where reel_id = v_reel.id;

    if to_regclass('public.messages') is not null then
      delete from public.messages where reel_id = v_reel.id;
    end if;

    delete from public.reels where id = v_reel.id;
  end loop;

  select coalesce(array_agg(id), '{}'::uuid[])
  into v_post_ids
  from public.posts
  where trade_id = p_trade_id;

  if coalesce(array_length(v_post_ids, 1), 0) > 0 then
    delete from public.likes where post_id = any (v_post_ids);
    delete from public.comments where post_id = any (v_post_ids);

    if to_regclass('public.saved_posts') is not null then
      delete from public.saved_posts where post_id = any (v_post_ids);
    end if;

    delete from public.notifications where post_id = any (v_post_ids);
    delete from public.posts where id = any (v_post_ids);
  end if;

  delete from public.notifications where trade_id = p_trade_id;
  delete from public.trade_likes where trade_id = p_trade_id;
  delete from public.trade_comments where trade_id = p_trade_id;

  if to_regclass('public.saved_trades') is not null then
    delete from public.saved_trades where trade_id = p_trade_id;
  end if;

  select coalesce(array_agg(id), '{}'::uuid[])
  into v_message_ids
  from public.messages
  where trade_id = p_trade_id;

  if coalesce(array_length(v_message_ids, 1), 0) > 0 then
    if to_regclass('public.message_likes') is not null then
      delete from public.message_likes where message_id = any (v_message_ids);
    end if;

    if to_regclass('public.message_comments') is not null then
      delete from public.message_comments where message_id = any (v_message_ids);
    end if;

    delete from public.messages where id = any (v_message_ids);
  end if;

  if to_regclass('public.room_messages') is not null then
    delete from public.room_messages where trade_id = p_trade_id;
    update public.room_messages
    set pinned_trade_id = null
    where pinned_trade_id = p_trade_id;
  end if;

  delete from public.trades where id = p_trade_id;
end;
$$;

notify pgrst, 'reload schema';
