-- Record payout analytics on the first payout (when no open cycle exists yet).

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
    );
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

  return v_new_cycle_id;
end;
$$;
