-- Recurring expenses stay one row. The app lists each date from the start
-- through today. Income is withdrawal or business money received.

alter table public.prop_firm_expenses
  add column if not exists recurrence text;

alter table public.prop_firm_expenses
  drop constraint if exists prop_firm_expenses_recurrence_check;
alter table public.prop_firm_expenses
  add constraint prop_firm_expenses_recurrence_check
  check (recurrence is null or recurrence in ('weekly', 'monthly', 'yearly'));

create table if not exists public.tracker_income (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  income_kind text not null,
  name text not null,
  project_label text,
  amount numeric(14, 2) not null,
  date_received date not null,
  payment_label text,
  notes text,
  recurrence text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tracker_income_kind_check check (income_kind in ('withdrawal', 'business')),
  constraint tracker_income_amount_positive check (
    amount > 0 and amount <= 999999999.99
  ),
  constraint tracker_income_name_length check (char_length(btrim(name)) between 1 and 120),
  constraint tracker_income_project_label_length check (
    project_label is null or char_length(btrim(project_label)) between 1 and 80
  ),
  constraint tracker_income_payment_label_length check (
    payment_label is null or char_length(btrim(payment_label)) <= 80
  ),
  constraint tracker_income_notes_length check (
    notes is null or char_length(btrim(notes)) <= 500
  ),
  constraint tracker_income_recurrence_check check (
    recurrence is null or recurrence in ('weekly', 'monthly', 'yearly')
  )
);

comment on table public.tracker_income is
  'Owner income for the expense tracker. Withdrawal or business receipts. Recurrence is expanded from date_received through today.';

create index if not exists tracker_income_user_date_idx
  on public.tracker_income (user_id, date_received desc, id desc);

create or replace function public.tracker_income_prepare_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.name := btrim(new.name);
  if new.income_kind is null or btrim(new.income_kind) = '' then
    new.income_kind := 'business';
  end if;
  if new.project_label is not null then
    new.project_label := nullif(btrim(new.project_label), '');
  end if;
  if new.payment_label is not null then
    new.payment_label := nullif(btrim(new.payment_label), '');
  end if;
  if new.notes is not null then
    new.notes := nullif(btrim(new.notes), '');
  end if;
  if new.recurrence is not null then
    new.recurrence := nullif(btrim(new.recurrence), '');
  end if;
  if new.income_kind = 'withdrawal' then
    new.project_label := null;
  end if;
  return new;
end;
$$;

drop trigger if exists tracker_income_prepare_row on public.tracker_income;
create trigger tracker_income_prepare_row
  before insert or update on public.tracker_income
  for each row
  execute function public.tracker_income_prepare_row();

alter table public.tracker_income enable row level security;

drop policy if exists "tracker_income_select_own" on public.tracker_income;
create policy "tracker_income_select_own"
  on public.tracker_income
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "tracker_income_insert_own" on public.tracker_income;
create policy "tracker_income_insert_own"
  on public.tracker_income
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "tracker_income_update_own" on public.tracker_income;
create policy "tracker_income_update_own"
  on public.tracker_income
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "tracker_income_delete_own" on public.tracker_income;
create policy "tracker_income_delete_own"
  on public.tracker_income
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

revoke all on table public.tracker_income from public, anon, authenticated;
grant select, insert, update, delete on table public.tracker_income to authenticated;
grant select, insert, update, delete on table public.tracker_income to service_role;
