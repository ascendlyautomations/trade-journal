-- Owner trading-analytics preferences.
-- Global answers live on trading_preferences. Dollar limits can be overridden
-- per account. A revision is appended when a saved rule changes so a later
-- evaluation can use the values that were active at that time.
-- Blank columns mean the rule is off. Nothing here assumes a trading style.

create or replace function public.trading_preference_symbols_ok(items text[])
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(bool_and(
    char_length(item) between 1 and 16
    and item ~ '^[A-Z0-9./-]+$'
  ), true)
  from unnest(coalesce(items, '{}'::text[])) as item;
$$;

revoke all on function public.trading_preference_symbols_ok(text[]) from public, anon, authenticated;

create table if not exists public.trading_preferences (
  user_id uuid primary key references auth.users (id) on delete cascade,
  trading_style text null,
  preferred_sessions text[] not null default '{}',
  primary_instruments text[] not null default '{}',
  target_rr numeric null,
  max_trades_per_day integer null,
  daily_loss_limit numeric null,
  consecutive_loss_pause integer null,
  breakeven_tolerance numeric null,
  daily_profit_target numeric null,
  max_drawdown_goal numeric null,
  planned_start_minute integer null,
  planned_end_minute integer null,
  wait_after_loss_minutes integer null,
  updated_at timestamptz not null default now(),
  constraint trading_preferences_style_check check (
    trading_style is null
    or trading_style in ('scalper', 'day_trader', 'swing_trader')
  ),
  constraint trading_preferences_sessions_check check (
    preferred_sessions <@ array['NY AM', 'NY Lunch', 'NY PM', 'London', 'Asia', 'After']::text[]
  ),
  constraint trading_preferences_instruments_check check (
    cardinality(primary_instruments) <= 12
    and public.trading_preference_symbols_ok(primary_instruments)
  ),
  constraint trading_preferences_target_rr_check check (
    target_rr is null or target_rr > 0
  ),
  constraint trading_preferences_max_trades_check check (
    max_trades_per_day is null or max_trades_per_day between 1 and 100
  ),
  constraint trading_preferences_daily_loss_check check (
    daily_loss_limit is null or daily_loss_limit > 0
  ),
  constraint trading_preferences_loss_pause_check check (
    consecutive_loss_pause is null or consecutive_loss_pause between 1 and 50
  ),
  constraint trading_preferences_breakeven_check check (
    breakeven_tolerance is null or breakeven_tolerance >= 0
  ),
  constraint trading_preferences_profit_target_check check (
    daily_profit_target is null or daily_profit_target > 0
  ),
  constraint trading_preferences_drawdown_goal_check check (
    max_drawdown_goal is null or max_drawdown_goal > 0
  ),
  constraint trading_preferences_wait_check check (
    wait_after_loss_minutes is null or wait_after_loss_minutes between 0 and 1440
  ),
  constraint trading_preferences_hours_check check (
    (planned_start_minute is null) = (planned_end_minute is null)
    and (planned_start_minute is null or planned_start_minute between 0 and 1439)
    and (planned_end_minute is null or planned_end_minute between 0 and 1439)
    and (
      planned_start_minute is null
      or planned_start_minute <> planned_end_minute
    )
  )
);

create table if not exists public.trading_preference_account_overrides (
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  overrides_daily_loss boolean not null default false,
  daily_loss_limit numeric null,
  overrides_daily_profit_target boolean not null default false,
  daily_profit_target numeric null,
  overrides_max_drawdown_goal boolean not null default false,
  max_drawdown_goal numeric null,
  updated_at timestamptz not null default now(),
  primary key (user_id, account_id),
  constraint trading_preference_overrides_daily_loss_check check (
    (
      overrides_daily_loss = false
      and daily_loss_limit is null
    )
    or (
      overrides_daily_loss = true
      and (daily_loss_limit is null or daily_loss_limit > 0)
    )
  ),
  constraint trading_preference_overrides_profit_target_check check (
    (
      overrides_daily_profit_target = false
      and daily_profit_target is null
    )
    or (
      overrides_daily_profit_target = true
      and (daily_profit_target is null or daily_profit_target > 0)
    )
  ),
  constraint trading_preference_overrides_drawdown_check check (
    (
      overrides_max_drawdown_goal = false
      and max_drawdown_goal is null
    )
    or (
      overrides_max_drawdown_goal = true
      and (max_drawdown_goal is null or max_drawdown_goal > 0)
    )
  )
);

create table if not exists public.trading_preference_revisions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid null,
  effective_from timestamptz not null default now(),
  trading_style text null,
  preferred_sessions text[] not null default '{}',
  primary_instruments text[] not null default '{}',
  target_rr numeric null,
  max_trades_per_day integer null,
  daily_loss_limit numeric null,
  consecutive_loss_pause integer null,
  breakeven_tolerance numeric null,
  daily_profit_target numeric null,
  max_drawdown_goal numeric null,
  planned_start_minute integer null,
  planned_end_minute integer null,
  wait_after_loss_minutes integer null,
  overrides_daily_loss boolean not null default false,
  overrides_daily_profit_target boolean not null default false,
  overrides_max_drawdown_goal boolean not null default false
);

create index if not exists trading_preference_revisions_lookup
  on public.trading_preference_revisions (user_id, effective_from desc);

comment on table public.trading_preferences is
  'Optional global trading-analytics preferences. Null means that rule is off.';

comment on table public.trading_preference_account_overrides is
  'Optional per-account dollar limits. A false override flag inherits the global value. A true flag with a null amount turns that limit off for the account.';

comment on table public.trading_preference_revisions is
  'Append-only snapshots. account_id null is the global rule set. A past trade is judged by the latest snapshot at or before its time.';

create or replace function public.trading_preferences_touch()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.trading_preferences_touch() from public, anon, authenticated;

drop trigger if exists trading_preferences_touch on public.trading_preferences;
create trigger trading_preferences_touch
before update on public.trading_preferences
for each row
execute function public.trading_preferences_touch();

drop trigger if exists trading_preference_account_overrides_touch
  on public.trading_preference_account_overrides;
create trigger trading_preference_account_overrides_touch
before update on public.trading_preference_account_overrides
for each row
execute function public.trading_preferences_touch();

create or replace function public.trading_preference_account_override_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.accounts a
    where a.id = new.account_id
      and a.user_id = new.user_id
  ) then
    raise exception 'account does not belong to this user';
  end if;
  return new;
end;
$$;

revoke all on function public.trading_preference_account_override_guard() from public, anon, authenticated;

drop trigger if exists trading_preference_account_override_guard
  on public.trading_preference_account_overrides;
create trigger trading_preference_account_override_guard
before insert or update on public.trading_preference_account_overrides
for each row
execute function public.trading_preference_account_override_guard();

create or replace function public.trading_preferences_record_revision()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_TABLE_NAME = 'trading_preferences' then
    if TG_OP = 'UPDATE'
      and old.trading_style is not distinct from new.trading_style
      and old.preferred_sessions is not distinct from new.preferred_sessions
      and old.primary_instruments is not distinct from new.primary_instruments
      and old.target_rr is not distinct from new.target_rr
      and old.max_trades_per_day is not distinct from new.max_trades_per_day
      and old.daily_loss_limit is not distinct from new.daily_loss_limit
      and old.consecutive_loss_pause is not distinct from new.consecutive_loss_pause
      and old.breakeven_tolerance is not distinct from new.breakeven_tolerance
      and old.daily_profit_target is not distinct from new.daily_profit_target
      and old.max_drawdown_goal is not distinct from new.max_drawdown_goal
      and old.planned_start_minute is not distinct from new.planned_start_minute
      and old.planned_end_minute is not distinct from new.planned_end_minute
      and old.wait_after_loss_minutes is not distinct from new.wait_after_loss_minutes
    then
      return new;
    end if;

    insert into public.trading_preference_revisions (
      user_id,
      account_id,
      trading_style,
      preferred_sessions,
      primary_instruments,
      target_rr,
      max_trades_per_day,
      daily_loss_limit,
      consecutive_loss_pause,
      breakeven_tolerance,
      daily_profit_target,
      max_drawdown_goal,
      planned_start_minute,
      planned_end_minute,
      wait_after_loss_minutes,
      overrides_daily_loss,
      overrides_daily_profit_target,
      overrides_max_drawdown_goal
    ) values (
      new.user_id,
      null,
      new.trading_style,
      new.preferred_sessions,
      new.primary_instruments,
      new.target_rr,
      new.max_trades_per_day,
      new.daily_loss_limit,
      new.consecutive_loss_pause,
      new.breakeven_tolerance,
      new.daily_profit_target,
      new.max_drawdown_goal,
      new.planned_start_minute,
      new.planned_end_minute,
      new.wait_after_loss_minutes,
      false,
      false,
      false
    );
  elsif TG_TABLE_NAME = 'trading_preference_account_overrides' then
    if TG_OP = 'UPDATE'
      and old.overrides_daily_loss is not distinct from new.overrides_daily_loss
      and old.daily_loss_limit is not distinct from new.daily_loss_limit
      and old.overrides_daily_profit_target is not distinct from new.overrides_daily_profit_target
      and old.daily_profit_target is not distinct from new.daily_profit_target
      and old.overrides_max_drawdown_goal is not distinct from new.overrides_max_drawdown_goal
      and old.max_drawdown_goal is not distinct from new.max_drawdown_goal
    then
      return new;
    end if;

    insert into public.trading_preference_revisions (
      user_id,
      account_id,
      daily_loss_limit,
      daily_profit_target,
      max_drawdown_goal,
      overrides_daily_loss,
      overrides_daily_profit_target,
      overrides_max_drawdown_goal
    ) values (
      new.user_id,
      new.account_id,
      new.daily_loss_limit,
      new.daily_profit_target,
      new.max_drawdown_goal,
      new.overrides_daily_loss,
      new.overrides_daily_profit_target,
      new.overrides_max_drawdown_goal
    );
  end if;

  return new;
end;
$$;

revoke all on function public.trading_preferences_record_revision() from public, anon, authenticated;

drop trigger if exists trading_preferences_record_revision on public.trading_preferences;
create trigger trading_preferences_record_revision
after insert or update on public.trading_preferences
for each row
execute function public.trading_preferences_record_revision();

drop trigger if exists trading_preference_account_overrides_record_revision
  on public.trading_preference_account_overrides;
create trigger trading_preference_account_overrides_record_revision
after insert or update on public.trading_preference_account_overrides
for each row
execute function public.trading_preferences_record_revision();

alter table public.trading_preferences enable row level security;
alter table public.trading_preference_account_overrides enable row level security;
alter table public.trading_preference_revisions enable row level security;

drop policy if exists "trading_preferences_select_own" on public.trading_preferences;
create policy "trading_preferences_select_own"
on public.trading_preferences
for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "trading_preferences_insert_own" on public.trading_preferences;
create policy "trading_preferences_insert_own"
on public.trading_preferences
for insert
to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists "trading_preferences_update_own" on public.trading_preferences;
create policy "trading_preferences_update_own"
on public.trading_preferences
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "trading_preferences_delete_own" on public.trading_preferences;
create policy "trading_preferences_delete_own"
on public.trading_preferences
for delete
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "trading_preference_overrides_select_own"
  on public.trading_preference_account_overrides;
create policy "trading_preference_overrides_select_own"
on public.trading_preference_account_overrides
for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "trading_preference_overrides_insert_own"
  on public.trading_preference_account_overrides;
create policy "trading_preference_overrides_insert_own"
on public.trading_preference_account_overrides
for insert
to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists "trading_preference_overrides_update_own"
  on public.trading_preference_account_overrides;
create policy "trading_preference_overrides_update_own"
on public.trading_preference_account_overrides
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "trading_preference_overrides_delete_own"
  on public.trading_preference_account_overrides;
create policy "trading_preference_overrides_delete_own"
on public.trading_preference_account_overrides
for delete
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "trading_preference_revisions_select_own"
  on public.trading_preference_revisions;
create policy "trading_preference_revisions_select_own"
on public.trading_preference_revisions
for select
to authenticated
using (user_id = (select auth.uid()));

revoke all on table public.trading_preferences from public, anon, authenticated;
grant select, insert, update, delete on table public.trading_preferences to authenticated;
grant select, insert, update, delete on table public.trading_preferences to service_role;

revoke all on table public.trading_preference_account_overrides from public, anon, authenticated;
grant select, insert, update, delete on table public.trading_preference_account_overrides to authenticated;
grant select, insert, update, delete on table public.trading_preference_account_overrides to service_role;

revoke all on table public.trading_preference_revisions from public, anon, authenticated;
grant select on table public.trading_preference_revisions to authenticated;
grant select, insert, update, delete on table public.trading_preference_revisions to service_role;
