-- Phase 2: Trading data integrity — payout cycle RPC return value, safe achievement
-- delete on payout removal, CSV import deduplication.

-- =============================================================================
-- 1. record_account_payout — return the completed (closed) cycle id, not the new open cycle
-- =============================================================================

create or replace function public.record_account_payout(
  p_account_id uuid,
  p_balance_after_payout numeric,
  p_payout_amount numeric,
  p_drawdown_behavior text,
  p_drawdown_floor_after_payout numeric,
  p_balance_before_payout numeric,
  p_remember_drawdown_behavior boolean default false
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
  v_completed_cycle_id uuid;
  v_next_cycle_number integer := 1;
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if p_balance_after_payout is null or p_balance_after_payout < 0 then
    raise exception 'Invalid balance after payout';
  end if;

  if p_payout_amount is null or p_payout_amount <= 0 then
    raise exception 'Invalid payout amount';
  end if;

  if p_drawdown_behavior not in ('reset_to_account', 'keep_trailing') then
    raise exception 'Invalid drawdown behavior';
  end if;

  if p_drawdown_floor_after_payout is null or p_drawdown_floor_after_payout < 0 then
    raise exception 'Invalid drawdown floor';
  end if;

  if p_balance_before_payout is null or p_balance_before_payout < 0 then
    raise exception 'Invalid balance before payout';
  end if;

  select a.user_id
  into v_account_user_id
  from public.accounts a
  where a.id = p_account_id;

  if v_account_user_id is null or v_account_user_id <> v_user_id then
    raise exception 'Account not found';
  end if;

  select coalesce(max(c.cycle_number), 0) + 1
  into v_next_cycle_number
  from public.account_payout_cycles c
  where c.account_id = p_account_id;

  select c.id
  into v_open_cycle_id
  from public.account_payout_cycles c
  where c.account_id = p_account_id
    and c.ended_at is null
  for update;

  if v_open_cycle_id is not null then
    update public.account_payout_cycles
    set
      ended_at = v_now,
      payout_amount = p_payout_amount,
      balance_before_payout = p_balance_before_payout,
      balance_after_payout = p_balance_after_payout,
      drawdown_behavior = p_drawdown_behavior,
      drawdown_floor_after_payout = p_drawdown_floor_after_payout
    where id = v_open_cycle_id;

    v_completed_cycle_id := v_open_cycle_id;
    v_next_cycle_number := v_next_cycle_number + 1;
  else
    insert into public.account_payout_cycles (
      account_id,
      user_id,
      cycle_start_balance,
      started_at,
      ended_at,
      payout_amount,
      balance_before_payout,
      balance_after_payout,
      drawdown_behavior,
      drawdown_floor_after_payout,
      cycle_number
    )
    values (
      p_account_id,
      v_user_id,
      p_balance_before_payout,
      v_now,
      v_now,
      p_payout_amount,
      p_balance_before_payout,
      p_balance_after_payout,
      p_drawdown_behavior,
      p_drawdown_floor_after_payout,
      v_next_cycle_number
    )
    returning id into v_completed_cycle_id;

    v_next_cycle_number := v_next_cycle_number + 1;
  end if;

  insert into public.account_payout_cycles (
    account_id,
    user_id,
    cycle_start_balance,
    started_at,
    payout_amount,
    balance_before_payout,
    balance_after_payout,
    drawdown_behavior,
    drawdown_floor_after_payout,
    cycle_number
  )
  values (
    p_account_id,
    v_user_id,
    p_balance_after_payout,
    v_now,
    null,
    null,
    p_balance_after_payout,
    p_drawdown_behavior,
    p_drawdown_floor_after_payout,
    v_next_cycle_number
  )
  returning id into v_new_cycle_id;

  update public.accounts
  set
    payout_drawdown_behavior = case
      when p_remember_drawdown_behavior then p_drawdown_behavior
      else payout_drawdown_behavior
    end,
    remember_payout_drawdown_behavior = case
      when p_remember_drawdown_behavior then true
      else remember_payout_drawdown_behavior
    end
  where id = p_account_id
    and user_id = v_user_id;

  return v_completed_cycle_id;
end;
$$;

-- =============================================================================
-- 2. delete_prop_payout — delete achievements only by explicit cycle metadata
-- =============================================================================

create or replace function public.delete_prop_payout(
  p_cycle_id uuid,
  p_drawdown_behavior text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_account_id uuid;
  v_amount numeric;
  v_ended_at timestamptz;
  v_balance_before numeric;
  v_closed_floor numeric;
  v_account_size text;
  v_size text;
  v_base numeric := 0;
  v_open_id uuid;
  v_open_floor numeric;
  v_floor numeric;
  v_open_number integer;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if p_drawdown_behavior not in ('reset_to_account', 'keep_trailing') then
    raise exception 'Invalid drawdown behavior';
  end if;

  select c.account_id, c.payout_amount, c.ended_at, c.balance_before_payout, c.drawdown_floor_after_payout
  into v_account_id, v_amount, v_ended_at, v_balance_before, v_closed_floor
  from public.account_payout_cycles c
  where c.id = p_cycle_id
    and c.user_id = v_user_id
    and c.ended_at is not null
    and c.payout_amount > 0
  for update;

  if v_account_id is null then
    raise exception 'Payout not found';
  end if;

  select a.account_size
  into v_account_size
  from public.accounts a
  where a.id = v_account_id
    and a.user_id = v_user_id;

  v_size := lower(replace(replace(replace(btrim(coalesce(v_account_size, '')), ',', ''), '$', ''), ' ', ''));
  if v_size ~ '^[0-9]+(\.[0-9]+)?k$' then
    v_base := substring(v_size from '^[0-9]+(\.[0-9]+)?')::numeric * 1000;
  elsif v_size ~ '^[0-9]+(\.[0-9]+)?$' then
    v_base := v_size::numeric;
  end if;
  if v_base < 0 then
    v_base := 0;
  end if;

  select c.id, c.drawdown_floor_after_payout, c.cycle_number
  into v_open_id, v_open_floor, v_open_number
  from public.account_payout_cycles c
  where c.account_id = v_account_id
    and c.ended_at is null
  for update;

  if p_drawdown_behavior = 'reset_to_account' then
    v_floor := v_base;
  else
    v_floor := coalesce(v_open_floor, v_closed_floor, v_base);
  end if;
  if v_floor < 0 then
    v_floor := 0;
  end if;

  if v_open_id is not null then
    update public.account_payout_cycles
    set
      cycle_start_balance = cycle_start_balance + v_amount,
      balance_after_payout = coalesce(balance_after_payout, cycle_start_balance) + v_amount,
      drawdown_behavior = p_drawdown_behavior,
      drawdown_floor_after_payout = v_floor
    where id = v_open_id;
  else
    select coalesce(max(c.cycle_number), 0) + 1
    into v_open_number
    from public.account_payout_cycles c
    where c.account_id = v_account_id;

    insert into public.account_payout_cycles (
      account_id,
      user_id,
      cycle_start_balance,
      started_at,
      payout_amount,
      balance_before_payout,
      balance_after_payout,
      drawdown_behavior,
      drawdown_floor_after_payout,
      cycle_number
    )
    values (
      v_account_id,
      v_user_id,
      coalesce(v_balance_before, v_amount),
      coalesce(v_ended_at, now()),
      null,
      null,
      coalesce(v_balance_before, v_amount),
      p_drawdown_behavior,
      v_floor,
      v_open_number
    );
  end if;

  delete from public.achievements a
  where a.user_id = v_user_id
    and a.achievement_type in ('prop_firm_payout', 'live_trading_payout', 'payout')
    and a.metadata->>'account_payout_cycle_id' = p_cycle_id::text;

  delete from public.prop_firm_payout_assignments
  where user_id = v_user_id
    and payout_key = 'cycle:' || p_cycle_id::text;

  delete from public.account_payout_cycles
  where id = p_cycle_id
    and user_id = v_user_id;
end;
$$;

-- =============================================================================
-- 3. CSV import deduplication (per user + account + fingerprint)
-- =============================================================================

create unique index if not exists trades_csv_import_dedupe_with_account_idx
  on public.trades (user_id, account_id, import_fingerprint)
  where import_source = 'csv'
    and import_fingerprint is not null
    and account_id is not null;

create unique index if not exists trades_csv_import_dedupe_no_account_idx
  on public.trades (user_id, import_fingerprint)
  where import_source = 'csv'
    and import_fingerprint is not null
    and account_id is null;
