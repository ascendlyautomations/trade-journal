-- Account edits can update the linked purchase date without creating a second expense.
-- Safe to run after 20261023163000, including when that migration was applied
-- before the purchase-date conflict update.

create or replace function public.upsert_prop_firm_account_purchase_expense(
  p_account_id uuid,
  p_user_id uuid,
  p_cost_per_account numeric,
  p_prop_firm_name text,
  p_expense_type text,
  p_date_paid date default current_date
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_owner uuid;
  v_name text := nullif(trim(coalesce(p_prop_firm_name, '')), '');
  v_id uuid;
begin
  select a.user_id
  into v_owner
  from public.accounts a
  where a.id = p_account_id;

  if v_owner is null or p_user_id is distinct from v_owner then
    raise exception 'Account not found';
  end if;

  if v_actor is not null and v_actor is distinct from v_owner then
    raise exception 'Account not found';
  end if;

  if p_cost_per_account is null or p_cost_per_account <= 0 then
    select e.id
    into v_id
    from public.prop_firm_expenses e
    where e.account_id = p_account_id
      and e.user_id = v_owner
      and e.source = 'account_purchase'
    limit 1;
    return v_id;
  end if;

  if v_name is null then
    raise exception 'Prop firm name is required';
  end if;

  if p_expense_type not in (
    'evaluation_purchase',
    'activation_fee',
    'reset_fee',
    'subscription_renewal',
    'other'
  ) then
    raise exception 'Invalid expense type';
  end if;

  if p_cost_per_account > 999999999.99 then
    raise exception 'Invalid purchase cost';
  end if;

  with upserted as (
    insert into public.prop_firm_expenses (
      user_id,
      prop_firm_name,
      expense_type,
      cost_per_account,
      quantity,
      date_paid,
      payment_label,
      notes,
      account_id,
      source
    )
    values (
      v_owner,
      v_name,
      p_expense_type,
      p_cost_per_account,
      1,
      coalesce(p_date_paid, current_date),
      null,
      null,
      p_account_id,
      'account_purchase'
    )
    on conflict (account_id) where source = 'account_purchase' and account_id is not null
    do update set
      cost_per_account = excluded.cost_per_account,
      date_paid = excluded.date_paid
    where public.prop_firm_expenses.cost_per_account is distinct from excluded.cost_per_account
       or public.prop_firm_expenses.date_paid is distinct from excluded.date_paid
    returning id
  )
  select upserted.id into v_id from upserted;

  if v_id is null then
    select e.id
    into v_id
    from public.prop_firm_expenses e
    where e.account_id = p_account_id
      and e.user_id = v_owner
      and e.source = 'account_purchase'
    limit 1;
  end if;

  return v_id;
end;
$$;

revoke all on function public.upsert_prop_firm_account_purchase_expense(
  uuid, uuid, numeric, text, text, date
) from public;

grant execute on function public.upsert_prop_firm_account_purchase_expense(
  uuid, uuid, numeric, text, text, date
) to authenticated, service_role;
