-- Trade entry no longer depends on accounts.can_add_trades.
-- Ownership stays mandatory. The free-plan create cap still counts
-- can_add_trades = true via accounts_enforce_free_plan_create_limit.
-- The column is retained so existing account payloads and that quota stay valid.

comment on column public.accounts.can_add_trades is
  'Retained for the free-plan account creation quota (accounts_enforce_free_plan_create_limit). Not a trade-entry authorization flag. Owned active accounts accept new trades.';

create or replace function public.trades_enforce_account_can_add_trades()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  acct_user uuid;
begin
  if new.account_id is null then
    return new;
  end if;

  select a.user_id
  into acct_user
  from public.accounts a
  where a.id::text = nullif(trim(new.account_id::text), '');

  -- No matching accounts row (legacy / orphaned name) — do not block.
  if acct_user is null then
    return new;
  end if;

  if acct_user is distinct from new.user_id then
    raise exception 'ACCOUNT_OWNERSHIP_MISMATCH';
  end if;

  return new;
end;
$$;

-- Not attached to a trigger. Kept so a future reattach cannot restore ACCOUNT_READ_ONLY.
create or replace function public.trades_enforce_free_plan_accounts()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return new;
end;
$$;

-- Old slot picker wrote can_add_trades = false. Calling it must not lock accounts.
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

  selected_count := coalesce(cardinality(p_account_ids), 0);

  if selected_count > 0 then
    if (
      select count(distinct x) from unnest(coalesce(p_account_ids, array[]::uuid[])) as t(x)
    ) <> selected_count then
      raise exception 'INVALID_ACCOUNT_SELECTION';
    end if;

    select count(*)::int into owned_count
    from public.accounts
    where user_id = uid
      and id = any (p_account_ids);

    if owned_count <> selected_count then
      raise exception 'INVALID_ACCOUNT_SELECTION';
    end if;
  end if;

  update public.accounts
  set can_add_trades = true
  where user_id = uid;
end;
$$;

-- Historical downgrade rows. Create quota is unchanged for users already at 3+ true flags.
update public.accounts
set can_add_trades = true
where can_add_trades is not true
  and coalesce(is_active, true);
