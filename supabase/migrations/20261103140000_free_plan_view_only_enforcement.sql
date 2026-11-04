-- Free plan: block client can_add_trades tampering; enforce view-only on trade UPDATE/DELETE.

-- Trusted bulk updates (slot RPC, service role restores).
create or replace function public.accounts_can_mutate_can_add_trades()
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(
    nullif(current_setting('tradetraxs.mutate_can_add_trades', true), ''),
    'off'
  ) = 'on';
$$;

create or replace function public.accounts_reject_client_can_add_trades_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if new.can_add_trades is not distinct from old.can_add_trades then
    return new;
  end if;

  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if public.accounts_can_mutate_can_add_trades() then
    return new;
  end if;

  raise exception 'CAN_ADD_TRADES_RPC_ONLY'
    using hint = 'Free-plan trade slots can only be changed via account selection.';
end;
$$;

drop trigger if exists accounts_reject_client_can_add_trades_update on public.accounts;
create trigger accounts_reject_client_can_add_trades_update
  before update of can_add_trades on public.accounts
  for each row
  execute function public.accounts_reject_client_can_add_trades_update();

-- Shared write gate for INSERT / UPDATE / DELETE on trades (Free + enforced limits).
create or replace function public.trades_enforce_account_can_add_trades()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  acct_user uuid;
  acct_can_add boolean;
  entry_enabled_count int;
  uid uuid;
  acct_id text;
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

  if public.profile_is_pro_user(uid) then
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

  if tg_op = 'INSERT' then
    select count(*)::int into entry_enabled_count
    from public.accounts
    where user_id = uid
      and can_add_trades = true;

    if coalesce(entry_enabled_count, 0) > 3 then
      raise exception 'ACCOUNT_SLOT_SELECTION_REQUIRED';
    end if;
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

drop trigger if exists trades_enforce_account_can_add_trades on public.trades;
create trigger trades_enforce_account_can_add_trades
  before insert on public.trades
  for each row
  execute function public.trades_enforce_account_can_add_trades();

drop trigger if exists trades_enforce_account_can_add_trades_update on public.trades;
create trigger trades_enforce_account_can_add_trades_update
  before update on public.trades
  for each row
  execute function public.trades_enforce_account_can_add_trades();

drop trigger if exists trades_enforce_account_can_add_trades_delete on public.trades;
create trigger trades_enforce_account_can_add_trades_delete
  before delete on public.trades
  for each row
  execute function public.trades_enforce_account_can_add_trades();

-- Slot picker + Pro restore may batch-update can_add_trades.
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
begin
  if uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  perform set_config('tradetraxs.mutate_can_add_trades', 'on', true);

  if public.profile_is_pro_user(uid) then
    update public.accounts
    set can_add_trades = true
    where user_id = uid;
    return;
  end if;

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
end;
$$;

revoke all on function public.select_free_plan_trade_accounts(uuid[]) from public;
grant execute on function public.select_free_plan_trade_accounts(uuid[]) to authenticated;

-- delete_own_trade: respect view-only accounts on Free.
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
     and not public.profile_is_pro_user(v_owner)
     and public.free_plan_limits_enforced() then
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

comment on function public.delete_own_trade(uuid) is
  'Deletes a trade owned by auth.uid(); blocks Free view-only account trades.';

grant execute on function public.delete_own_trade(uuid) to authenticated;

notify pgrst, 'reload schema';
