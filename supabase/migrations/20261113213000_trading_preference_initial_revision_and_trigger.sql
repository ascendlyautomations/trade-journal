-- Ensure every saved trading_preferences row has at least one global revision snapshot,
-- and that INSERT creates a revision anchored to updated_at (not a silent omission).
-- Forward-only: uses trading_preferences.updated_at / account override updated_at only.

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
      effective_from,
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
      case when TG_OP = 'INSERT' then coalesce(new.updated_at, now()) else now() end,
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
      effective_from,
      daily_loss_limit,
      daily_profit_target,
      max_drawdown_goal,
      overrides_daily_loss,
      overrides_daily_profit_target,
      overrides_max_drawdown_goal
    ) values (
      new.user_id,
      new.account_id,
      case when TG_OP = 'INSERT' then coalesce(new.updated_at, now()) else now() end,
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

-- Backfill missing global revisions from the current preferences row (effective_from = updated_at).
insert into public.trading_preference_revisions (
  user_id,
  account_id,
  effective_from,
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
)
select
  tp.user_id,
  null,
  tp.updated_at,
  tp.trading_style,
  tp.preferred_sessions,
  tp.primary_instruments,
  tp.target_rr,
  tp.max_trades_per_day,
  tp.daily_loss_limit,
  tp.consecutive_loss_pause,
  tp.breakeven_tolerance,
  tp.daily_profit_target,
  tp.max_drawdown_goal,
  tp.planned_start_minute,
  tp.planned_end_minute,
  tp.wait_after_loss_minutes,
  tp.max_risk_per_trade,
  tp.min_acceptable_rr,
  tp.allowed_trading_days,
  tp.max_contracts_per_trade,
  tp.max_weekly_loss,
  tp.stop_after_daily_profit_target,
  tp.max_trades_per_day_scope,
  tp.daily_loss_limit_scope,
  tp.daily_profit_rules_scope,
  tp.max_weekly_loss_scope,
  false,
  false,
  false
from public.trading_preferences tp
where not exists (
  select 1
  from public.trading_preference_revisions r
  where r.user_id = tp.user_id
    and r.account_id is null
);

-- Backfill missing per-account override revisions.
insert into public.trading_preference_revisions (
  user_id,
  account_id,
  effective_from,
  daily_loss_limit,
  daily_profit_target,
  max_drawdown_goal,
  overrides_daily_loss,
  overrides_daily_profit_target,
  overrides_max_drawdown_goal
)
select
  o.user_id,
  o.account_id,
  o.updated_at,
  o.daily_loss_limit,
  o.daily_profit_target,
  o.max_drawdown_goal,
  o.overrides_daily_loss,
  o.overrides_daily_profit_target,
  o.overrides_max_drawdown_goal
from public.trading_preference_account_overrides o
where not exists (
  select 1
  from public.trading_preference_revisions r
  where r.user_id = o.user_id
    and r.account_id = o.account_id
);
