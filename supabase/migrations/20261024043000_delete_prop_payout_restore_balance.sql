-- Delete a completed prop payout and put its amount back on the open cycle.
-- The caller chooses where the drawdown floor moves after the payout is gone.

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
    and (
      a.metadata->>'account_payout_cycle_id' = p_cycle_id::text
      or (
        a.account_id = v_account_id
        and a.value_numeric is not null
        and abs(a.value_numeric - v_amount) < 0.02
        and a.achieved_at between v_ended_at - interval '3 days' and v_ended_at + interval '3 days'
      )
    );

  delete from public.prop_firm_payout_assignments
  where user_id = v_user_id
    and payout_key = 'cycle:' || p_cycle_id::text;

  delete from public.account_payout_cycles
  where id = p_cycle_id
    and user_id = v_user_id;
end;
$$;

revoke all on function public.delete_prop_payout(uuid, text) from public, anon;
grant execute on function public.delete_prop_payout(uuid, text) to authenticated;
grant execute on function public.delete_prop_payout(uuid, text) to service_role;

comment on function public.delete_prop_payout(uuid, text) is
  'Removes a completed prop payout, adds the amount back to the open cycle balance, and moves the drawdown floor.';
