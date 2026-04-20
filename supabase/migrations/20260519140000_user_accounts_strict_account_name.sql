-- Strict account limits by account_name (not trade deletes). Replace prior account_key + triggers.

drop trigger if exists trades_sync_user_accounts on public.trades;
drop trigger if exists trades_enforce_free_plan_accounts on public.trades;

drop function if exists public.trades_sync_user_accounts();
drop function if exists public.trades_enforce_free_plan_accounts();
drop function if exists public.compute_trade_account_key(text, text, text);

drop table if exists public.user_accounts;

create table public.user_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_name text not null,
  account_type text not null default 'manual',
  created_at timestamptz not null default now(),
  unique (user_id, account_name)
);

create index if not exists user_accounts_user_id_idx on public.user_accounts (user_id);

alter table public.user_accounts enable row level security;

drop policy if exists "Users select own user_accounts" on public.user_accounts;
drop policy if exists "Users insert own user_accounts" on public.user_accounts;

create policy "Users select own user_accounts"
  on public.user_accounts
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "Users insert own user_accounts"
  on public.user_accounts
  for insert
  to authenticated
  with check (user_id = auth.uid());

grant select, insert on table public.user_accounts to authenticated;
