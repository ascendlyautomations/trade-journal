-- Free-plan trade-entry slots: permanent accounts, read-only via can_add_trades.

-- Keep DB Pro check aligned with client `isProActive` (includes future trial_end).
create or replace function public.profile_is_pro_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(p.is_pro, false)
    or lower(trim(coalesce(p.subscription_status::text, ''))) in ('active', 'trialing')
    or (p.trial_end is not null and p.trial_end > now())
  from public.profiles p
  where p.id = p_user_id;
$$;

alter table public.accounts
  add column if not exists can_add_trades boolean not null default true;

comment on column public.accounts.can_add_trades is
  'When true, new trades may target this account. Free plan allows at most 3 true. False = historical/read-only; never deleted.';

-- Atomic Free-plan selection: 0–3 accounts keep can_add_trades = true.
create or replace function public.select_free_plan_trade_accounts(p_account_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  selected_count int;
  owned_count int;
begin
  if uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- Pro / trialing: re-enable everything and exit.
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

-- Re-enable all accounts when user is Pro (used after upgrade).
create or replace function public.enable_all_account_trade_entry(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null then
    return;
  end if;
  update public.accounts
  set can_add_trades = true
  where user_id = p_user_id;
end;
$$;

revoke all on function public.enable_all_account_trade_entry(uuid) from public;
-- Service role / webhook use service key; also allow authenticated self-call via API with service.
grant execute on function public.enable_all_account_trade_entry(uuid) to service_role;

-- Reject trade inserts targeting read-only accounts or while Free slot selection is pending.
create or replace function public.trades_enforce_account_can_add_trades()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  acct_user uuid;
  acct_can_add boolean;
  entry_enabled_count int;
  user_is_pro boolean;
begin
  if new.account_id is null then
    return new;
  end if;

  select a.user_id, a.can_add_trades
  into acct_user, acct_can_add
  from public.accounts a
  -- trades.account_id is text; accounts.id is uuid — compare as text.
  where a.id::text = nullif(trim(new.account_id::text), '');

  -- No matching accounts row (legacy / orphaned name) — do not block.
  if acct_user is null then
    return new;
  end if;

  if acct_user is distinct from new.user_id then
    raise exception 'ACCOUNT_OWNERSHIP_MISMATCH';
  end if;

  user_is_pro := public.profile_is_pro_user(new.user_id);

  if user_is_pro then
    return new;
  end if;

  select count(*)::int into entry_enabled_count
  from public.accounts
  where user_id = new.user_id
    and can_add_trades = true;

  if entry_enabled_count > 3 then
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
