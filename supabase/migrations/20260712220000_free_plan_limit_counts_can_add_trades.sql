-- Free plan account create limit: count only can_add_trades = true (not historical).

create or replace function public.accounts_enforce_free_plan_create_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  entry_enabled_count int;
begin
  -- Pro / trial: unlimited.
  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  -- Creating a read-only historical row does not consume a Free slot.
  if new.can_add_trades is not true then
    return new;
  end if;

  select count(*)::int into entry_enabled_count
  from public.accounts
  where user_id = new.user_id
    and can_add_trades = true;

  if coalesce(entry_enabled_count, 0) >= 3 then
    raise exception 'FREE_PLAN_ACCOUNT_LIMIT'
      using hint = 'Free plan allows up to 3 active accounts. Upgrade to Pro for unlimited accounts.';
  end if;

  return new;
end;
$$;

drop trigger if exists accounts_enforce_free_plan_create_limit on public.accounts;
create trigger accounts_enforce_free_plan_create_limit
  before insert on public.accounts
  for each row
  execute function public.accounts_enforce_free_plan_create_limit();

-- If the legacy trade free-account function still exists, align its count to can_add_trades.
-- (Trigger may be absent; do not re-attach — trade entry is gated by can_add_trades.)
create or replace function public.trades_enforce_free_plan_accounts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  entry_enabled_count int;
  account_allows boolean;
begin
  if coalesce(new.mode, '') = 'backtest' then
    return new;
  end if;

  if lower(trim(coalesce(new.account_type::text, ''))) = 'imported' then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  if new.account_id is not null and trim(new.account_id::text) <> '' then
    select a.can_add_trades
    into account_allows
    from public.accounts a
    where a.id::text = nullif(trim(new.account_id::text), '')
      and a.user_id = new.user_id;

    if found then
      if account_allows is not true then
        raise exception 'ACCOUNT_READ_ONLY';
      end if;
      return new;
    end if;
  end if;

  select count(*)::int into entry_enabled_count
  from public.accounts
  where user_id = new.user_id
    and can_add_trades = true;

  if coalesce(entry_enabled_count, 0) >= 3 then
    raise exception 'FREE_PLAN_ACCOUNT_LIMIT'
      using hint = 'Free plan allows up to 3 active accounts. Upgrade to Pro for unlimited accounts.';
  end if;

  return new;
end;
$$;
