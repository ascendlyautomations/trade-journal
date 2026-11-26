-- Fix copy trading group deletion when trades sit on view-only (copy-linked) accounts.
--
-- Root cause: deleting a group unlinks historical trades (client PATCH + FK ON DELETE SET NULL).
-- The trades_enforce_account_can_add_trades trigger treats every UPDATE as a journal write and
-- raises ACCOUNT_READ_ONLY for Free / view-only copy-linked accounts, so unlink + group DELETE fail.

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

  -- Metadata-only unlink when deleting a copy trading group (no journal field changes).
  if tg_op = 'UPDATE'
     and old.copy_trading_group_id is not null
     and new.copy_trading_group_id is null
     and (to_jsonb(old) - 'copy_trading_group_id')
         = (to_jsonb(new) - 'copy_trading_group_id')
  then
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

comment on function public.trades_enforce_account_can_add_trades() is
  'Enforces Free trade-slot write rules. Allows copy_trading_group_id-only unlink when deleting a copy group.';