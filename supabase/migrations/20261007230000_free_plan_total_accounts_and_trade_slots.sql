-- Free plan v3: 3 trading accounts total (creation cap); up to 3 trade-entry slots via can_add_trades.

comment on column public.accounts.can_add_trades is
  'When true, new trades may target this account on Free. Pro users ignore this flag. False = read-only with history preserved. Account creation is capped by total rows, not this flag.';

-- ---------------------------------------------------------------------------
-- Creation limit: count every owned account (active, archived, read-only).
-- ---------------------------------------------------------------------------

create or replace function public.accounts_enforce_free_plan_create_limit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  total_count int;
begin
  if not public.free_plan_limits_enforced() then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  perform pg_advisory_xact_lock(
    872342,
    hashtext(new.user_id::text || ':free_plan_account_create')
  );

  select count(*)::int into total_count
  from public.accounts
  where user_id = new.user_id;

  if coalesce(total_count, 0) >= 3 then
    raise exception 'FREE_PLAN_ACCOUNT_LIMIT'
      using hint = 'Free plan allows up to 3 trading accounts total. Upgrade to TraxPro for unlimited accounts.';
  end if;

  return new;
end;
$$;

drop trigger if exists accounts_enforce_free_plan_create_limit on public.accounts;
create trigger accounts_enforce_free_plan_create_limit
  before insert on public.accounts
  for each row
  execute function public.accounts_enforce_free_plan_create_limit();

-- ---------------------------------------------------------------------------
-- Trade entry: Pro bypass; Free requires can_add_trades and <= 3 enabled slots.
-- ---------------------------------------------------------------------------

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
begin
  if new.account_id is null then
    return new;
  end if;

  select a.user_id, a.can_add_trades
  into acct_user, acct_can_add
  from public.accounts a
  where a.id::text = nullif(trim(new.account_id::text), '');

  if acct_user is null then
    return new;
  end if;

  if acct_user is distinct from new.user_id then
    raise exception 'ACCOUNT_OWNERSHIP_MISMATCH';
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  if not public.free_plan_limits_enforced() then
    return new;
  end if;

  select count(*)::int into entry_enabled_count
  from public.accounts
  where user_id = new.user_id
    and can_add_trades = true;

  if coalesce(entry_enabled_count, 0) > 3 then
    raise exception 'ACCOUNT_SLOT_SELECTION_REQUIRED';
  end if;

  if acct_can_add is not true then
    raise exception 'ACCOUNT_READ_ONLY';
  end if;

  return new;
end;
$$;

drop trigger if exists trades_enforce_account_can_add_trades on public.trades;
create trigger trades_enforce_account_can_add_trades
  before insert on public.trades
  for each row
  execute function public.trades_enforce_account_can_add_trades();

-- ---------------------------------------------------------------------------
-- Downgrade slot selection + Pro re-enable (0–3 active trade-entry accounts).
-- ---------------------------------------------------------------------------

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

  if public.profile_is_pro_user(uid) then
    update public.accounts
    set can_add_trades = true
    where user_id = uid;
    return;
  end if;

  if not public.free_plan_limits_enforced() then
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
