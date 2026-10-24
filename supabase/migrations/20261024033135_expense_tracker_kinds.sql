-- Expense tracker kinds on the existing prop firm expense table.
-- Prop firm rows stay the default. Other kinds store a vendor name in
-- prop_firm_name, an optional project label, and a custom category.

alter table public.prop_firm_expenses
  add column if not exists tracker_kind text not null default 'prop_firm',
  add column if not exists project_label text,
  add column if not exists custom_category text;

alter table public.prop_firm_expenses
  drop constraint if exists prop_firm_expenses_tracker_kind_check;
alter table public.prop_firm_expenses
  add constraint prop_firm_expenses_tracker_kind_check
  check (tracker_kind in ('prop_firm', 'business', 'trading_tools', 'other'));

alter table public.prop_firm_expenses
  drop constraint if exists prop_firm_expenses_project_label_length;
alter table public.prop_firm_expenses
  add constraint prop_firm_expenses_project_label_length
  check (project_label is null or char_length(btrim(project_label)) between 1 and 80);

alter table public.prop_firm_expenses
  drop constraint if exists prop_firm_expenses_custom_category_length;
alter table public.prop_firm_expenses
  add constraint prop_firm_expenses_custom_category_length
  check (custom_category is null or char_length(btrim(custom_category)) between 1 and 80);

create or replace function public.prop_firm_expenses_prepare_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.prop_firm_name := btrim(new.prop_firm_name);
  if new.tracker_kind is null or btrim(new.tracker_kind) = '' then
    new.tracker_kind := 'prop_firm';
  end if;
  if new.payment_label is not null then
    new.payment_label := nullif(btrim(new.payment_label), '');
  end if;
  if new.notes is not null then
    new.notes := nullif(btrim(new.notes), '');
  end if;
  if new.tracker_kind = 'prop_firm' then
    new.project_label := null;
    new.custom_category := null;
  else
    new.expense_type := 'other';
    new.account_id := null;
    new.source := 'manual';
    if new.project_label is not null then
      new.project_label := nullif(btrim(new.project_label), '');
    end if;
    if new.custom_category is not null then
      new.custom_category := nullif(btrim(new.custom_category), '');
    end if;
  end if;
  return new;
end;
$$;

create table if not exists public.expense_categories (
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, name),
  constraint expense_categories_name_length check (char_length(btrim(name)) between 1 and 80)
);

create unique index if not exists expense_categories_user_name_lower_idx
  on public.expense_categories (user_id, lower(name));

comment on table public.expense_categories is
  'Owner-created expense categories for non-prop tracker rows.';

create or replace function public.expense_categories_prepare_row()
returns trigger
language plpgsql
as $$
begin
  new.name := btrim(new.name);
  return new;
end;
$$;

drop trigger if exists expense_categories_prepare_row on public.expense_categories;
create trigger expense_categories_prepare_row
  before insert or update on public.expense_categories
  for each row
  execute function public.expense_categories_prepare_row();

alter table public.expense_categories enable row level security;

drop policy if exists "expense_categories_select_own" on public.expense_categories;
create policy "expense_categories_select_own"
  on public.expense_categories
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "expense_categories_insert_own" on public.expense_categories;
create policy "expense_categories_insert_own"
  on public.expense_categories
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "expense_categories_delete_own" on public.expense_categories;
create policy "expense_categories_delete_own"
  on public.expense_categories
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

revoke all on table public.expense_categories from public, anon, authenticated;
grant select, insert, delete on table public.expense_categories to authenticated;
grant select, insert, update, delete on table public.expense_categories to service_role;
