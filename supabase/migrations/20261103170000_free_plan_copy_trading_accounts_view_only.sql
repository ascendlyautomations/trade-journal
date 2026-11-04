-- Copy Trading–linked accounts stay view-only on Free (not trade-entry slots).

create or replace function public.user_copy_trading_account_ids(p_user_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select distinct cta.account_id
  from public.copy_trading_groups g
  inner join public.copy_trading_group_accounts cta on cta.group_id = g.id
  where g.user_id = p_user_id;
$$;

comment on function public.user_copy_trading_account_ids(uuid) is
  'Account ids linked to any Copy Trading group owned by the user.';

create or replace function public.enforce_copy_trading_accounts_view_only(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_user_id is null then
    return;
  end if;

  perform set_config('tradetraxs.mutate_can_add_trades', 'on', true);

  update public.accounts
  set can_add_trades = false
  where user_id = p_user_id
    and id in (select public.user_copy_trading_account_ids(p_user_id));
end;
$$;

comment on function public.enforce_copy_trading_accounts_view_only(uuid) is
  'Forces can_add_trades = false on Copy Trading–linked accounts (Free slot RPCs / downgrade).';

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

  perform public.enforce_copy_trading_accounts_view_only(p_user_id);
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

    if exists (
      select 1
      from unnest(p_account_ids) as sel(id)
      where sel.id in (select public.user_copy_trading_account_ids(uid))
    ) then
      raise exception 'COPY_TRADING_ACCOUNT_NOT_ELIGIBLE';
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

  perform public.enforce_copy_trading_accounts_view_only(uid);

  update public.profiles
  set free_plan_trade_slots_confirmed_epoch = v_epoch
  where id = uid;
end;
$$;

-- Backfill: Free trade-slot users with copy-linked accounts still active.
do $$
begin
  perform set_config('tradetraxs.mutate_can_add_trades', 'on', true);

  update public.accounts a
  set can_add_trades = false
  from public.profiles p
  where a.user_id = p.id
    and public.profile_trade_slots_pro(p) = false
    and a.can_add_trades = true
    and a.id in (select public.user_copy_trading_account_ids(a.user_id));
end;
$$;
