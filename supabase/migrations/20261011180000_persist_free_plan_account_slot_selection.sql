-- Free downgrade slot picks must persist even while entitlement enforcement is off.
-- The previous function set every owned account back to can_add_trades = true in that
-- case, so the client reloaded more than 3 entry-enabled accounts and reopened the picker.
-- Accounts are never deleted. Unselected rows stay read-only.

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
