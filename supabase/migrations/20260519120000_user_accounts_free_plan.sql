-- Permanent registry of manual (non-imported) trading accounts for free-plan enforcement.
-- Imported CSV trades use account_type = 'imported' and never insert here.
-- Counting uses this table so deleting trades cannot reset the account limit.

create or replace function public.compute_trade_account_key(
  account_type text,
  account_size text,
  account_id text
)
returns text
language sql
immutable
parallel safe
as $$
  select concat_ws(
    '|',
    lower(trim(coalesce(account_type, ''))),
    trim(coalesce(account_size, '')),
    trim(coalesce(account_id, ''))
  );
$$;

create table if not exists public.user_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  account_name text,
  account_type text not null,
  account_size text,
  account_id text,
  account_key text not null,
  created_at timestamptz not null default now(),
  unique (user_id, account_key)
);

create index if not exists user_accounts_user_id_idx on public.user_accounts (user_id);

alter table public.user_accounts enable row level security;

drop policy if exists "Users select own user_accounts" on public.user_accounts;
create policy "Users select own user_accounts"
  on public.user_accounts
  for select
  to authenticated
  using (user_id = auth.uid());

grant select on table public.user_accounts to authenticated;

-- Replace free-plan BEFORE trigger: count registered accounts from user_accounts (not trades).

create or replace function public.trades_enforce_free_plan_accounts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_pro_user boolean;
  new_key text;
  registration_count int;
  key_registered boolean;
begin
  if coalesce(new.mode, '') = 'backtest' then
    return new;
  end if;

  if lower(trim(coalesce(new.account_type::text, ''))) = 'imported' then
    return new;
  end if;

  is_pro_user := false;
  select coalesce(p.is_pro, false)
    or lower(trim(coalesce(p.subscription_status::text, ''))) = 'active'
  into is_pro_user
  from public.profiles p
  where p.id = new.user_id;

  if not found then
    is_pro_user := false;
  end if;

  if coalesce(is_pro_user, false) then
    return new;
  end if;

  new_key := public.compute_trade_account_key(
    new.account_type::text,
    new.account_size::text,
    new.account_id::text
  );

  select count(*)::int
  into registration_count
  from public.user_accounts ua
  where ua.user_id = new.user_id;

  select exists (
    select 1
    from public.user_accounts ua
    where ua.user_id = new.user_id
      and ua.account_key = new_key
  )
  into key_registered;

  if coalesce(registration_count, 0) >= 1 and not coalesce(key_registered, false) then
    raise exception 'FREE_PLAN_ACCOUNT_LIMIT'
      using hint = 'Free plan allows only one trading account. Upgrade to Pro for unlimited accounts.';
  end if;

  return new;
end;
$$;

drop trigger if exists trades_sync_user_accounts on public.trades;

create or replace function public.trades_sync_user_accounts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ak text;
begin
  if coalesce(new.mode, '') = 'backtest' then
    return new;
  end if;

  if lower(trim(coalesce(new.account_type::text, ''))) = 'imported' then
    return new;
  end if;

  ak := public.compute_trade_account_key(
    new.account_type::text,
    new.account_size::text,
    new.account_id::text
  );

  insert into public.user_accounts as ua (
    user_id,
    account_name,
    account_type,
    account_size,
    account_id,
    account_key
  )
  values (
    new.user_id,
    new.account_name,
    lower(trim(coalesce(new.account_type::text, ''))),
    new.account_size,
    new.account_id,
    ak
  )
  on conflict (user_id, account_key) do update set
    account_name = coalesce(excluded.account_name, ua.account_name),
    account_type = coalesce(excluded.account_type, ua.account_type),
    account_size = coalesce(excluded.account_size, ua.account_size),
    account_id = coalesce(excluded.account_id, ua.account_id);

  return new;
end;
$$;

create trigger trades_sync_user_accounts
after insert or update on public.trades
for each row
execute procedure public.trades_sync_user_accounts();

-- Backfill from historical trades (one row per distinct account_key, earliest trade wins for metadata).

insert into public.user_accounts (
  user_id,
  account_name,
  account_type,
  account_size,
  account_id,
  account_key,
  created_at
)
select distinct on (t.user_id, public.compute_trade_account_key(
    t.account_type::text,
    t.account_size::text,
    t.account_id::text
  ))
  t.user_id,
  t.account_name,
  lower(trim(coalesce(t.account_type::text, ''))),
  t.account_size,
  t.account_id,
  public.compute_trade_account_key(
    t.account_type::text,
    t.account_size::text,
    t.account_id::text
  ),
  t.created_at
from public.trades t
where coalesce(t.mode, '') <> 'backtest'
  and lower(trim(coalesce(t.account_type::text, ''))) <> 'imported'
order by t.user_id, public.compute_trade_account_key(
    t.account_type::text,
    t.account_size::text,
    t.account_id::text
  ), t.created_at asc
on conflict (user_id, account_key) do nothing;
