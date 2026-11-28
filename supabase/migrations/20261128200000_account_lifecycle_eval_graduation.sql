-- Evaluation → Funded lifecycle: shared slot id, server-only graduation RPC.

begin;

alter table public.accounts
  add column if not exists account_lifecycle_id uuid,
  add column if not exists graduated_to_account_id uuid references public.accounts (id) on delete set null,
  add column if not exists graduated_from_account_id uuid references public.accounts (id) on delete set null;

update public.accounts
set account_lifecycle_id = id
where account_lifecycle_id is null;

alter table public.accounts
  alter column account_lifecycle_id set not null;

create index if not exists accounts_account_lifecycle_id_idx
  on public.accounts (user_id, account_lifecycle_id);

create unique index if not exists accounts_one_successor_per_eval_uidx
  on public.accounts (graduated_from_account_id)
  where graduated_from_account_id is not null;

comment on column public.accounts.account_lifecycle_id is
  'Immutable free-plan slot / prop-firm lifecycle id. Eval and funded successor share one id.';
comment on column public.accounts.graduated_to_account_id is
  'Evaluation row: funded successor account id after graduation.';
comment on column public.accounts.graduated_from_account_id is
  'Funded row: source evaluation account id. Set only via graduate_eval_to_funded.';

-- ---------------------------------------------------------------------------
-- Slot counting (distinct lifecycle ids)
-- ---------------------------------------------------------------------------

create or replace function public.user_distinct_account_slot_count(p_user_id uuid)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select count(distinct a.account_lifecycle_id)::int
  from public.accounts a
  where a.user_id = p_user_id;
$$;

comment on function public.user_distinct_account_slot_count(uuid) is
  'Free-plan logical account slots (eval + funded successor = one slot).';

-- ---------------------------------------------------------------------------
-- Defaults + immutability on INSERT
-- ---------------------------------------------------------------------------

create or replace function public.accounts_lifecycle_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.account_lifecycle_id is null then
    new.account_lifecycle_id := new.id;
  end if;

  if new.account_lifecycle_id is distinct from new.id
     and coalesce(current_setting('tradetraxs.account_lifecycle_graduation', true), '') is distinct from 'on'
  then
    raise exception 'ACCOUNT_LIFECYCLE_UNAUTHORIZED'
      using hint = 'Lifecycle slot reuse requires graduate_eval_to_funded.';
  end if;

  if new.graduated_from_account_id is not null
     and coalesce(current_setting('tradetraxs.account_lifecycle_graduation', true), '') is distinct from 'on'
  then
    raise exception 'ACCOUNT_LIFECYCLE_UNAUTHORIZED';
  end if;

  return new;
end;
$$;

drop trigger if exists accounts_lifecycle_before_insert on public.accounts;
create trigger accounts_lifecycle_before_insert
  before insert on public.accounts
  for each row
  execute function public.accounts_lifecycle_before_insert();

-- ---------------------------------------------------------------------------
-- Graduation invariants + immutable lifecycle links on UPDATE
-- ---------------------------------------------------------------------------

create or replace function public.accounts_enforce_lifecycle_on_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if old.account_lifecycle_id is distinct from new.account_lifecycle_id then
    raise exception 'ACCOUNT_LIFECYCLE_IMMUTABLE';
  end if;

  if old.graduated_from_account_id is distinct from new.graduated_from_account_id then
    if coalesce(current_setting('tradetraxs.account_lifecycle_graduation', true), '') is distinct from 'on'
       and not public.rate_limit_is_service_role()
    then
      raise exception 'ACCOUNT_LIFECYCLE_IMMUTABLE';
    end if;
  end if;

  if old.graduated_to_account_id is distinct from new.graduated_to_account_id then
    if coalesce(current_setting('tradetraxs.account_lifecycle_graduation', true), '') is distinct from 'on'
       and not public.rate_limit_is_service_role()
    then
      raise exception 'ACCOUNT_LIFECYCLE_IMMUTABLE';
    end if;
  end if;

  if old.graduated_to_account_id is not null then
  -- Completed evaluation: never re-enable trade entry or change mode/category.
    if new.can_add_trades is true and old.can_add_trades is not true then
      raise exception 'GRADUATED_EVAL_READ_ONLY';
    end if;
    if new.can_add_trades is true and pg_trigger_depth() = 0
       and coalesce(current_setting('tradetraxs.mutate_can_add_trades', true), '') is distinct from 'on'
    then
      raise exception 'GRADUATED_EVAL_READ_ONLY';
    end if;
    if lower(trim(coalesce(new.mode, ''))) is distinct from lower(trim(coalesce(old.mode, ''))) then
      raise exception 'GRADUATED_EVAL_LOCKED';
    end if;
    if trim(coalesce(new.category, '')) is distinct from trim(coalesce(old.category, '')) then
      raise exception 'GRADUATED_EVAL_LOCKED';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists accounts_enforce_lifecycle_on_update on public.accounts;
create trigger accounts_enforce_lifecycle_on_update
  before update on public.accounts
  for each row
  execute function public.accounts_enforce_lifecycle_on_update();

-- ---------------------------------------------------------------------------
-- Free plan creation limit: distinct lifecycle slots (eval+funded = 1)
-- ---------------------------------------------------------------------------

create or replace function public.accounts_enforce_free_plan_create_limit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  distinct_count int;
  slot_exists boolean;
  new_slot uuid;
begin
  if not public.free_plan_limits_enforced() then
    return new;
  end if;

  if public.profile_is_pro_user(new.user_id) then
    return new;
  end if;

  perform pg_advisory_xact_lock(
    872342,
    hashtext(new.user_id::text || ':free_plan_account_create')
  );

  new_slot := new.account_lifecycle_id;

  select public.user_distinct_account_slot_count(new.user_id) into distinct_count;

  select exists (
    select 1
    from public.accounts a
    where a.user_id = new.user_id
      and a.account_lifecycle_id = new_slot
  ) into slot_exists;

  if not coalesce(slot_exists, false)
     and coalesce(distinct_count, 0) >= 3
  then
    raise exception 'FREE_PLAN_ACCOUNT_LIMIT'
      using hint = 'Free plan allows up to 3 trading account slots. Upgrade to TraxPro for unlimited accounts.';
  end if;

  return new;
end;
$$;

drop trigger if exists accounts_enforce_free_plan_create_limit on public.accounts;
create trigger accounts_enforce_free_plan_create_limit
  before insert on public.accounts
  for each row
  execute function public.accounts_enforce_free_plan_create_limit();

-- ---------------------------------------------------------------------------
-- Downgrade / pending selection: distinct slots, not row count
-- ---------------------------------------------------------------------------

create or replace function public.free_plan_trade_slots_pending(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (
      select
        public.user_distinct_account_slot_count(p_user_id) > 3
        and coalesce(p.free_plan_trade_slots_confirmed_epoch, 0)
          < coalesce(p.free_plan_trade_slots_epoch, 0)
      from public.profiles p
      where p.id = p_user_id
    ),
    false
  );
$$;

create or replace function public.apply_free_plan_trade_slot_downgrade(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_epoch bigint;
  v_account_count int;
  v_slot_count int;
begin
  if p_user_id is null then
    return;
  end if;

  update public.profiles
  set free_plan_trade_slots_epoch = coalesce(free_plan_trade_slots_epoch, 0) + 1
  where id = p_user_id
  returning free_plan_trade_slots_epoch into v_epoch;

  select count(*)::int into v_account_count
  from public.accounts
  where user_id = p_user_id;

  select public.user_distinct_account_slot_count(p_user_id) into v_slot_count;

  perform set_config('tradetraxs.mutate_can_add_trades', 'on', true);

  if coalesce(v_slot_count, 0) <= 3 and coalesce(v_account_count, 0) <= 3 then
    update public.accounts
    set can_add_trades = true
    where user_id = p_user_id
      and graduated_to_account_id is null;

    update public.profiles
    set free_plan_trade_slots_confirmed_epoch = v_epoch
    where id = p_user_id;
  elsif coalesce(v_slot_count, 0) <= 3 then
    update public.accounts
    set can_add_trades = false
    where user_id = p_user_id
      and graduated_to_account_id is not null;

    update public.profiles
    set free_plan_trade_slots_confirmed_epoch = v_epoch
    where id = p_user_id;
  else
    update public.accounts
    set can_add_trades = false
    where user_id = p_user_id;

    update public.profiles
    set free_plan_trade_slots_confirmed_epoch = coalesce(free_plan_trade_slots_confirmed_epoch, 0)
    where id = p_user_id;
  end if;

  perform public.enforce_copy_trading_accounts_view_only(p_user_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- graduate_eval_to_funded
-- ---------------------------------------------------------------------------

create or replace function public.graduate_eval_to_funded(
  p_eval_account_id uuid,
  p_payload jsonb
)
returns public.accounts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_eval public.accounts%rowtype;
  v_funded public.accounts%rowtype;
  v_name text;
  v_mode text;
  v_transfer_can_add boolean;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if p_eval_account_id is null or p_payload is null then
    raise exception 'INVALID_GRADUATION_PAYLOAD';
  end if;

  select * into v_eval
  from public.accounts
  where id = p_eval_account_id
    and user_id = v_uid
  for update;

  if not found then
    raise exception 'ACCOUNT_NOT_FOUND';
  end if;

  if lower(trim(coalesce(v_eval.category, ''))) not in ('prop firm', 'propfirm') then
    raise exception 'GRADUATION_PROP_FIRM_ONLY';
  end if;

  if lower(trim(coalesce(v_eval.mode, ''))) not in ('eval', 'evaluation') then
    raise exception 'GRADUATION_EVAL_ONLY';
  end if;

  if v_eval.graduated_to_account_id is not null then
    raise exception 'GRADUATION_ALREADY_COMPLETED';
  end if;

  v_name := nullif(trim(coalesce(p_payload->>'name', '')), '');
  if v_name is null then
    raise exception 'ACCOUNT_NAME_REQUIRED';
  end if;

  v_mode := lower(trim(coalesce(p_payload->>'mode', 'funded')));
  if v_mode not in ('funded') then
    raise exception 'GRADUATION_FUNDED_MODE_REQUIRED';
  end if;

  v_transfer_can_add := coalesce(v_eval.can_add_trades, false);

  perform pg_advisory_xact_lock(
    872343,
    hashtext(v_uid::text || ':graduate:' || p_eval_account_id::text)
  );

  perform set_config('tradetraxs.account_lifecycle_graduation', 'on', true);
  perform set_config('tradetraxs.mutate_can_add_trades', 'on', true);

  insert into public.accounts (
    user_id,
    name,
    account_size,
    account_number,
    category,
    mode,
    is_active,
    can_add_trades,
    show_in_account_dropdowns,
    account_lifecycle_id,
    graduated_from_account_id,
    consistency,
    max_drawdown,
    daily_drawdown,
    profit_target,
    winning_days,
    winning_day_threshold,
    payout_drawdown_behavior,
    remember_payout_drawdown_behavior
  )
  values (
    v_uid,
    v_name,
    nullif(trim(coalesce(p_payload->>'account_size', '')), ''),
    nullif(trim(coalesce(p_payload->>'account_number', '')), ''),
    coalesce(nullif(trim(coalesce(p_payload->>'category', '')), ''), v_eval.category),
    'Funded',
    true,
    v_transfer_can_add,
    true,
    v_eval.account_lifecycle_id,
    v_eval.id,
    (p_payload->>'consistency')::numeric,
    (p_payload->>'max_drawdown')::numeric,
    (p_payload->>'daily_drawdown')::numeric,
    (p_payload->>'profit_target')::numeric,
    (p_payload->>'winning_days')::numeric,
    (p_payload->>'winning_day_threshold')::numeric,
    coalesce(p_payload->>'payout_drawdown_behavior', v_eval.payout_drawdown_behavior),
    coalesce((p_payload->>'remember_payout_drawdown_behavior')::boolean, v_eval.remember_payout_drawdown_behavior)
  )
  returning * into v_funded;

  update public.accounts
  set
    can_add_trades = false,
    show_in_account_dropdowns = false,
    graduated_to_account_id = v_funded.id
  where id = v_eval.id;

  perform public.enforce_copy_trading_accounts_view_only(v_uid);

  return v_funded;
end;
$$;

revoke all on function public.graduate_eval_to_funded(uuid, jsonb) from public;
grant execute on function public.graduate_eval_to_funded(uuid, jsonb) to authenticated;

comment on function public.graduate_eval_to_funded(uuid, jsonb) is
  'Atomically create funded successor sharing free-plan slot; freeze evaluation as read-only history.';

commit;