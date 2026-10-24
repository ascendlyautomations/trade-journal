-- Explicit prop-firm label for an existing payout.
-- This does not change the payout amount, account balance, or payout record.

create table if not exists public.prop_firm_payout_assignments (
  user_id uuid not null references auth.users (id) on delete cascade,
  payout_key text not null,
  prop_firm_name text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, payout_key),
  constraint prop_firm_payout_assignments_key_check check (
    payout_key ~ '^(ledger|cycle):[0-9a-fA-F-]{36}$'
  ),
  constraint prop_firm_payout_assignments_name_check check (
    char_length(btrim(prop_firm_name)) between 1 and 120
  )
);

create or replace function public.prop_firm_payout_assignments_prepare()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.prop_firm_name := btrim(new.prop_firm_name);
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists prop_firm_payout_assignments_prepare on public.prop_firm_payout_assignments;
create trigger prop_firm_payout_assignments_prepare
before insert or update on public.prop_firm_payout_assignments
for each row
execute function public.prop_firm_payout_assignments_prepare();

alter table public.prop_firm_payout_assignments enable row level security;

drop policy if exists "prop_firm_payout_assignments_select_own" on public.prop_firm_payout_assignments;
create policy "prop_firm_payout_assignments_select_own"
on public.prop_firm_payout_assignments
for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "prop_firm_payout_assignments_insert_own" on public.prop_firm_payout_assignments;
create policy "prop_firm_payout_assignments_insert_own"
on public.prop_firm_payout_assignments
for insert
to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists "prop_firm_payout_assignments_update_own" on public.prop_firm_payout_assignments;
create policy "prop_firm_payout_assignments_update_own"
on public.prop_firm_payout_assignments
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "prop_firm_payout_assignments_delete_own" on public.prop_firm_payout_assignments;
create policy "prop_firm_payout_assignments_delete_own"
on public.prop_firm_payout_assignments
for delete
to authenticated
using (user_id = (select auth.uid()));

revoke all on table public.prop_firm_payout_assignments from public, anon, authenticated;
grant select, insert, update, delete on table public.prop_firm_payout_assignments to authenticated;
grant select, insert, update, delete on table public.prop_firm_payout_assignments to service_role;

comment on table public.prop_firm_payout_assignments is
  'Owner-chosen prop firm label for a payout. Does not change payout amounts or balances.';
