-- Extend payout cycles + account preferences for full payout workflow.

alter table public.accounts
  add column if not exists payout_drawdown_behavior text
    check (
      payout_drawdown_behavior is null
      or payout_drawdown_behavior in ('reset_to_account', 'keep_trailing')
    ),
  add column if not exists remember_payout_drawdown_behavior boolean not null default false;

comment on column public.accounts.payout_drawdown_behavior is
  'Last selected drawdown behavior after payout (reset to account base vs keep trailing floor).';
comment on column public.accounts.remember_payout_drawdown_behavior is
  'When true, preselect payout_drawdown_behavior on future payouts for this account.';

alter table public.account_payout_cycles
  add column if not exists balance_before_payout numeric null,
  add column if not exists balance_after_payout numeric null,
  add column if not exists drawdown_behavior text
    check (
      drawdown_behavior is null
      or drawdown_behavior in ('reset_to_account', 'keep_trailing')
    ),
  add column if not exists drawdown_floor_after_payout numeric null,
  add column if not exists cycle_number integer null;

comment on column public.account_payout_cycles.balance_before_payout is
  'Account balance immediately before the payout (closed cycles).';
comment on column public.account_payout_cycles.balance_after_payout is
  'Account balance immediately after the payout; new cycle starts here.';
comment on column public.account_payout_cycles.drawdown_floor_after_payout is
  'Trailing drawdown floor in effect at cycle start (open) or after payout (closed).';
comment on column public.account_payout_cycles.cycle_number is
  'Sequential payout cycle number for this account (1-based).';

drop function if exists public.record_account_payout_cycle(uuid, numeric);

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

revoke all on function public.record_account_payout(
  uuid,
  numeric,
  numeric,
  text,
  numeric,
  numeric,
  boolean
) from public;

grant execute on function public.record_account_payout(
  uuid,
  numeric,
  numeric,
  text,
  numeric,
  numeric,
  boolean
) to authenticated;
