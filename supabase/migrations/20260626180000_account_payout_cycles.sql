-- Payout cycles for funded prop firm accounts.
-- Each cycle tracks progress toward the next payout without deleting trades.

create table if not exists public.account_payout_cycles (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  started_at timestamptz not null default now(),
  ended_at timestamptz null,
  cycle_start_balance numeric not null,
  payout_amount numeric null,
  note text null,
  created_at timestamptz not null default now(),
  constraint account_payout_cycles_cycle_start_balance_nonneg
    check (cycle_start_balance >= 0)
);

create index if not exists account_payout_cycles_account_id_idx
  on public.account_payout_cycles (account_id);

create index if not exists account_payout_cycles_user_id_idx
  on public.account_payout_cycles (user_id);

create unique index if not exists account_payout_cycles_one_open_per_account_idx
  on public.account_payout_cycles (account_id)
  where ended_at is null;

alter table public.account_payout_cycles enable row level security;

drop policy if exists "account_payout_cycles_select_own" on public.account_payout_cycles;
create policy "account_payout_cycles_select_own"
  on public.account_payout_cycles
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "account_payout_cycles_insert_own" on public.account_payout_cycles;
create policy "account_payout_cycles_insert_own"
  on public.account_payout_cycles
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.accounts a
      where a.id = account_id
        and a.user_id = auth.uid()
    )
  );

drop policy if exists "account_payout_cycles_update_own" on public.account_payout_cycles;
create policy "account_payout_cycles_update_own"
  on public.account_payout_cycles
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update on table public.account_payout_cycles to authenticated;

-- Close the open cycle (if any) and start a new one atomically.
create or replace function public.record_account_payout_cycle(
  p_account_id uuid,
  p_cycle_start_balance numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_account_user_id uuid;
  v_open_cycle_id uuid;
  v_new_cycle_id uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if p_cycle_start_balance is null or p_cycle_start_balance < 0 then
    raise exception 'Invalid cycle start balance';
  end if;

  select a.user_id
  into v_account_user_id
  from public.accounts a
  where a.id = p_account_id;

  if v_account_user_id is null or v_account_user_id <> v_user_id then
    raise exception 'Account not found';
  end if;

  select c.id
  into v_open_cycle_id
  from public.account_payout_cycles c
  where c.account_id = p_account_id
    and c.ended_at is null
  for update;

  if v_open_cycle_id is not null then
    update public.account_payout_cycles
    set ended_at = now()
    where id = v_open_cycle_id;
  end if;

  insert into public.account_payout_cycles (
    account_id,
    user_id,
    cycle_start_balance,
    started_at
  )
  values (
    p_account_id,
    v_user_id,
    p_cycle_start_balance,
    now()
  )
  returning id into v_new_cycle_id;

  return v_new_cycle_id;
end;
$$;

revoke all on function public.record_account_payout_cycle(uuid, numeric) from public;
grant execute on function public.record_account_payout_cycle(uuid, numeric) to authenticated;
