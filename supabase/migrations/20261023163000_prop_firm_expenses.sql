-- Owner-managed prop firm expense history.
-- Account deletion unlinks the row (ON DELETE SET NULL) and keeps the expense.
-- One account_purchase row per trading account; later saves update that row.

create table if not exists public.prop_firm_expenses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  prop_firm_name text not null,
  expense_type text not null,
  cost_per_account numeric(14, 2) not null,
  quantity integer not null,
  total_cost numeric(18, 2) generated always as (round(cost_per_account * quantity, 2)) stored,
  date_paid date not null,
  payment_label text null,
  notes text null,
  account_id uuid null references public.accounts (id) on delete set null,
  source text not null default 'manual',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint prop_firm_expenses_type_check check (
    expense_type in (
      'evaluation_purchase',
      'activation_fee',
      'reset_fee',
      'subscription_renewal',
      'other'
    )
  ),
  constraint prop_firm_expenses_source_check check (
    source in ('manual', 'account_purchase')
  ),
  constraint prop_firm_expenses_cost_positive check (
    cost_per_account > 0
    and cost_per_account <= 999999999.99
  ),
  constraint prop_firm_expenses_quantity_positive check (
    quantity >= 1
    and quantity <= 10000
  ),
  constraint prop_firm_expenses_firm_name_length check (
    char_length(trim(prop_firm_name)) between 1 and 120
  ),
  constraint prop_firm_expenses_payment_label_length check (
    payment_label is null or char_length(trim(payment_label)) <= 80
  ),
  constraint prop_firm_expenses_notes_length check (
    notes is null or char_length(trim(notes)) <= 500
  )
);

comment on table public.prop_firm_expenses is
  'Owner prop-firm fees (evals, activations, resets, renewals). Independent of payout balances and trading P&L.';
comment on column public.prop_firm_expenses.payment_label is
  'User-entered bank or card label. Never a PAN, token, or processor id.';
comment on column public.prop_firm_expenses.account_id is
  'Optional linked trading account. Null after the account is deleted so expense history remains.';
comment on column public.prop_firm_expenses.source is
  'manual = expense tracker. account_purchase = created from Account Purchase Cost and updated in place.';
comment on column public.prop_firm_expenses.total_cost is
  'cost_per_account * quantity, stored so clients do not recompute money with floats.';

create index if not exists prop_firm_expenses_user_date_idx
  on public.prop_firm_expenses (user_id, date_paid desc, id desc);

create index if not exists prop_firm_expenses_account_id_idx
  on public.prop_firm_expenses (account_id)
  where account_id is not null;

create unique index if not exists prop_firm_expenses_account_purchase_uidx
  on public.prop_firm_expenses (account_id)
  where source = 'account_purchase' and account_id is not null;

create or replace function public.prop_firm_expenses_prepare_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.prop_firm_name := trim(new.prop_firm_name);
  if new.payment_label is not null then
    new.payment_label := nullif(trim(new.payment_label), '');
  end if;
  if new.notes is not null then
    new.notes := nullif(trim(new.notes), '');
  end if;
  return new;
end;
$$;

drop trigger if exists prop_firm_expenses_prepare_row on public.prop_firm_expenses;
create trigger prop_firm_expenses_prepare_row
  before insert or update on public.prop_firm_expenses
  for each row
  execute function public.prop_firm_expenses_prepare_row();

alter table public.prop_firm_expenses enable row level security;

drop policy if exists "prop_firm_expenses_select_own" on public.prop_firm_expenses;
create policy "prop_firm_expenses_select_own"
  on public.prop_firm_expenses
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "prop_firm_expenses_insert_own" on public.prop_firm_expenses;
create policy "prop_firm_expenses_insert_own"
  on public.prop_firm_expenses
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and (
      account_id is null
      or exists (
        select 1
        from public.accounts a
        where a.id = account_id
          and a.user_id = (select auth.uid())
      )
    )
  );

drop policy if exists "prop_firm_expenses_update_own" on public.prop_firm_expenses;
create policy "prop_firm_expenses_update_own"
  on public.prop_firm_expenses
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and (
      account_id is null
      or exists (
        select 1
        from public.accounts a
        where a.id = account_id
          and a.user_id = (select auth.uid())
      )
    )
  );

drop policy if exists "prop_firm_expenses_delete_own" on public.prop_firm_expenses;
create policy "prop_firm_expenses_delete_own"
  on public.prop_firm_expenses
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

revoke all on table public.prop_firm_expenses from anon, authenticated;
grant select, insert, update, delete on table public.prop_firm_expenses to authenticated;
grant select, insert, update, delete on table public.prop_firm_expenses to service_role;

-- Idempotent account-purchase expense. Authenticated callers must own the account.
-- Service role (broker link) has no auth.uid(); p_user_id must still match the account owner.
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
