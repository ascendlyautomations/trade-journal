-- Copy Trading Groups (PRO): journal one trade across multiple linked accounts.

create table if not exists public.copy_trading_groups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint copy_trading_groups_name_not_blank check (char_length(trim(name)) > 0),
  constraint copy_trading_groups_user_name_unique unique (user_id, name)
);

create table if not exists public.copy_trading_group_accounts (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.copy_trading_groups (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  constraint copy_trading_group_accounts_unique unique (group_id, account_id)
);

create index if not exists copy_trading_groups_user_id_idx
  on public.copy_trading_groups (user_id);

create index if not exists copy_trading_group_accounts_group_id_idx
  on public.copy_trading_group_accounts (group_id);

create index if not exists copy_trading_group_accounts_account_id_idx
  on public.copy_trading_group_accounts (account_id);

alter table public.trades
  add column if not exists copy_trading_group_id uuid
  references public.copy_trading_groups (id) on delete set null;

create index if not exists trades_copy_trading_group_id_idx
  on public.trades (copy_trading_group_id)
  where copy_trading_group_id is not null;

-- Keep updated_at fresh on group rename.
create or replace function public.copy_trading_groups_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists copy_trading_groups_set_updated_at on public.copy_trading_groups;
create trigger copy_trading_groups_set_updated_at
  before update on public.copy_trading_groups
  for each row
  execute function public.copy_trading_groups_set_updated_at();

-- Ensure group member accounts belong to the same user.
create or replace function public.copy_trading_group_accounts_owner_check()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  group_owner uuid;
  account_owner uuid;
begin
  select user_id into group_owner
  from public.copy_trading_groups
  where id = new.group_id;

  if group_owner is null then
    raise exception 'Copy trading group not found';
  end if;

  select user_id into account_owner
  from public.accounts
  where id = new.account_id;

  if account_owner is null then
    raise exception 'Trading account not found';
  end if;

  if group_owner <> account_owner or new.user_id <> group_owner then
    raise exception 'Copy trading group accounts must belong to the group owner';
  end if;

  return new;
end;
$$;

drop trigger if exists copy_trading_group_accounts_owner_check on public.copy_trading_group_accounts;
create trigger copy_trading_group_accounts_owner_check
  before insert or update on public.copy_trading_group_accounts
  for each row
  execute function public.copy_trading_group_accounts_owner_check();

alter table public.copy_trading_groups enable row level security;
alter table public.copy_trading_group_accounts enable row level security;

drop policy if exists "copy_trading_groups_select_own" on public.copy_trading_groups;
create policy "copy_trading_groups_select_own"
  on public.copy_trading_groups
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "copy_trading_groups_insert_own" on public.copy_trading_groups;
create policy "copy_trading_groups_insert_own"
  on public.copy_trading_groups
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "copy_trading_groups_update_own" on public.copy_trading_groups;
create policy "copy_trading_groups_update_own"
  on public.copy_trading_groups
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "copy_trading_groups_delete_own" on public.copy_trading_groups;
create policy "copy_trading_groups_delete_own"
  on public.copy_trading_groups
  for delete
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "copy_trading_group_accounts_select_own" on public.copy_trading_group_accounts;
create policy "copy_trading_group_accounts_select_own"
  on public.copy_trading_group_accounts
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "copy_trading_group_accounts_insert_own" on public.copy_trading_group_accounts;
create policy "copy_trading_group_accounts_insert_own"
  on public.copy_trading_group_accounts
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "copy_trading_group_accounts_update_own" on public.copy_trading_group_accounts;
create policy "copy_trading_group_accounts_update_own"
  on public.copy_trading_group_accounts
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "copy_trading_group_accounts_delete_own" on public.copy_trading_group_accounts;
create policy "copy_trading_group_accounts_delete_own"
  on public.copy_trading_group_accounts
  for delete
  to authenticated
  using (user_id = auth.uid());
