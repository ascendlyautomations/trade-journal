-- Expanded optional trading rules and account scope for limits that aggregate by day or week.

create or replace function public.trading_preference_weekdays_ok(items text[])
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(bool_and(
    item in ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')
  ), true)
  from unnest(coalesce(items, '{}'::text[])) as item;
$$;

revoke all on function public.trading_preference_weekdays_ok(text[]) from public, anon, authenticated;

create or replace function public.trading_preference_scope_ok(value text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select value in ('combined', 'per_account');
$$;

revoke all on function public.trading_preference_scope_ok(text) from public, anon, authenticated;

alter table public.trading_preferences
  add column if not exists max_risk_per_trade numeric null,
  add column if not exists min_acceptable_rr numeric null,
  add column if not exists allowed_trading_days text[] not null default '{}',
  add column if not exists max_contracts_per_trade integer null,
  add column if not exists max_weekly_loss numeric null,
  add column if not exists stop_after_daily_profit_target boolean not null default false,
  add column if not exists max_trades_per_day_scope text not null default 'combined',
  add column if not exists daily_loss_limit_scope text not null default 'combined',
  add column if not exists daily_profit_rules_scope text not null default 'combined',
  add column if not exists max_weekly_loss_scope text not null default 'combined';

alter table public.trading_preferences
  drop constraint if exists trading_preferences_max_risk_check,
  add constraint trading_preferences_max_risk_check check (
    max_risk_per_trade is null or max_risk_per_trade > 0
  ),
  drop constraint if exists trading_preferences_min_acceptable_rr_check,
  add constraint trading_preferences_min_acceptable_rr_check check (
    min_acceptable_rr is null or min_acceptable_rr > 0
  ),
  drop constraint if exists trading_preferences_allowed_days_check,
  add constraint trading_preferences_allowed_days_check check (
    cardinality(allowed_trading_days) <= 7
    and public.trading_preference_weekdays_ok(allowed_trading_days)
  ),
  drop constraint if exists trading_preferences_max_contracts_check,
  add constraint trading_preferences_max_contracts_check check (
    max_contracts_per_trade is null or max_contracts_per_trade between 1 and 10000
  ),
  drop constraint if exists trading_preferences_max_weekly_loss_check,
  add constraint trading_preferences_max_weekly_loss_check check (
    max_weekly_loss is null or max_weekly_loss > 0
  ),
  drop constraint if exists trading_preferences_scope_checks,
  add constraint trading_preferences_scope_checks check (
    public.trading_preference_scope_ok(max_trades_per_day_scope)
    and public.trading_preference_scope_ok(daily_loss_limit_scope)
    and public.trading_preference_scope_ok(daily_profit_rules_scope)
    and public.trading_preference_scope_ok(max_weekly_loss_scope)
  ),
  drop constraint if exists trading_preferences_profit_stop_requires_target,
  add constraint trading_preferences_profit_stop_requires_target check (
  not stop_after_daily_profit_target or daily_profit_target is not null
);

alter table public.trading_preference_revisions
  add column if not exists max_risk_per_trade numeric null,
  add column if not exists min_acceptable_rr numeric null,
  add column if not exists allowed_trading_days text[] not null default '{}',
  add column if not exists max_contracts_per_trade integer null,
  add column if not exists max_weekly_loss numeric null,
  add column if not exists stop_after_daily_profit_target boolean not null default false,
  add column if not exists max_trades_per_day_scope text not null default 'combined',
  add column if not exists daily_loss_limit_scope text not null default 'combined',
  add column if not exists daily_profit_rules_scope text not null default 'combined',
  add column if not exists max_weekly_loss_scope text not null default 'combined';

alter table public.trades
  add column if not exists dollar_risk numeric null;

alter table public.trades
  drop constraint if exists trades_dollar_risk_check,
  add constraint trades_dollar_risk_check check (
    dollar_risk is null or dollar_risk > 0
  );

comment on column public.trades.dollar_risk is
  'Optional planned dollar risk at entry. Used for max-risk trading rules when present; not inferred from P&L.';

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
      and old.max_risk_per_trade is not distinct from new.max_risk_per_trade
      and old.min_acceptable_rr is not distinct from new.min_acceptable_rr
      and old.allowed_trading_days is not distinct from new.allowed_trading_days
      and old.max_contracts_per_trade is not distinct from new.max_contracts_per_trade
      and old.max_weekly_loss is not distinct from new.max_weekly_loss
      and old.stop_after_daily_profit_target is not distinct from new.stop_after_daily_profit_target
      and old.max_trades_per_day_scope is not distinct from new.max_trades_per_day_scope
      and old.daily_loss_limit_scope is not distinct from new.daily_loss_limit_scope
      and old.daily_profit_rules_scope is not distinct from new.daily_profit_rules_scope
      and old.max_weekly_loss_scope is not distinct from new.max_weekly_loss_scope
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
      max_risk_per_trade,
      min_acceptable_rr,
      allowed_trading_days,
      max_contracts_per_trade,
      max_weekly_loss,
      stop_after_daily_profit_target,
      max_trades_per_day_scope,
      daily_loss_limit_scope,
      daily_profit_rules_scope,
      max_weekly_loss_scope,
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
      new.max_risk_per_trade,
      new.min_acceptable_rr,
      new.allowed_trading_days,
      new.max_contracts_per_trade,
      new.max_weekly_loss,
      new.stop_after_daily_profit_target,
      new.max_trades_per_day_scope,
      new.daily_loss_limit_scope,
      new.daily_profit_rules_scope,
      new.max_weekly_loss_scope,
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
