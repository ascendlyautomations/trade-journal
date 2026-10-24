-- Preferred tax-reserve percentage for the prop firm expense tracker.
-- One row per user. The page treats a missing row as 25%.
-- This percentage is a budgeting preference, not a tax determination.

create table if not exists public.prop_firm_expense_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  tax_reserve_percent numeric(5, 2) not null,
  updated_at timestamptz not null default now(),
  constraint prop_firm_expense_settings_percent_check check (
    tax_reserve_percent > 0
    and tax_reserve_percent <= 100
  )
);

create or replace function public.prop_firm_expense_settings_touch()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists prop_firm_expense_settings_touch on public.prop_firm_expense_settings;
create trigger prop_firm_expense_settings_touch
before update on public.prop_firm_expense_settings
for each row
execute function public.prop_firm_expense_settings_touch();

alter table public.prop_firm_expense_settings enable row level security;

drop policy if exists "prop_firm_expense_settings_select_own" on public.prop_firm_expense_settings;
create policy "prop_firm_expense_settings_select_own"
on public.prop_firm_expense_settings
for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "prop_firm_expense_settings_insert_own" on public.prop_firm_expense_settings;
create policy "prop_firm_expense_settings_insert_own"
on public.prop_firm_expense_settings
for insert
to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists "prop_firm_expense_settings_update_own" on public.prop_firm_expense_settings;
create policy "prop_firm_expense_settings_update_own"
on public.prop_firm_expense_settings
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

revoke all on table public.prop_firm_expense_settings from public, anon, authenticated;
grant select, insert, update on table public.prop_firm_expense_settings to authenticated;
grant select, insert, update, delete on table public.prop_firm_expense_settings to service_role;

comment on table public.prop_firm_expense_settings is
  'Owner budgeting preference for an estimated prop-firm tax reserve. Not a tax liability.';
