-- Fix: trades.account_id (text) vs accounts.id (uuid) in can_add_trades trigger.
-- Restores trade inserts for Pro/trial/Free (type mismatch only; logic unchanged).

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
