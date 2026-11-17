import type { SupabaseClient } from "@supabase/supabase-js"
import {
  emptyTradingPreferenceGlobal,
  isTradingStyleId,
  booleanFromDatabase,
  normalizeAllowedTradingDays,
  normalizePreferenceInstruments,
  normalizePreferenceSessions,
  normalizeTradingRuleScope,
  numericFromDatabase,
  type TradingPreferenceAccountOverride,
  type TradingPreferenceGlobal,
  type TradingPreferenceRevision,
  type TradingStyleId,
} from "@/lib/analytics/tradingPreferences"
import { createTradingPreferenceBundleCache } from "./tradingPreferenceBundleCache"

const GLOBAL_SELECT = `
  user_id,
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
  updated_at
`

const OVERRIDE_SELECT = `
  user_id,
  account_id,
  overrides_daily_loss,
  daily_loss_limit,
  overrides_daily_profit_target,
  daily_profit_target,
  overrides_max_drawdown_goal,
  max_drawdown_goal,
  updated_at
`

const REVISION_SELECT = `
  id,
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
`

function styleFromDatabase(value: unknown): TradingStyleId | null {
  const raw = value == null ? null : String(value)
  return isTradingStyleId(raw) ? raw : null
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value.filter((item): item is string => typeof item === "string")
}

export function mapTradingPreferenceGlobal(
  row: Record<string, unknown> | null,
  userId: string
): TradingPreferenceGlobal {
  if (!row) return emptyTradingPreferenceGlobal(userId)
  return {
    userId: String(row.user_id ?? userId),
    tradingStyle: styleFromDatabase(row.trading_style),
    preferredSessions: normalizePreferenceSessions(stringList(row.preferred_sessions)),
    primaryInstruments: normalizePreferenceInstruments(stringList(row.primary_instruments)),
    targetRr: numericFromDatabase(row.target_rr),
    maxTradesPerDay: numericFromDatabase(row.max_trades_per_day),
    dailyLossLimit: numericFromDatabase(row.daily_loss_limit),
    consecutiveLossPause: numericFromDatabase(row.consecutive_loss_pause),
    breakevenTolerance: numericFromDatabase(row.breakeven_tolerance),
    dailyProfitTarget: numericFromDatabase(row.daily_profit_target),
    maxDrawdownGoal: numericFromDatabase(row.max_drawdown_goal),
    plannedStartMinute: numericFromDatabase(row.planned_start_minute),
    plannedEndMinute: numericFromDatabase(row.planned_end_minute),
    waitAfterLossMinutes: numericFromDatabase(row.wait_after_loss_minutes),
    maxRiskPerTrade: numericFromDatabase(row.max_risk_per_trade),
    minAcceptableRr: numericFromDatabase(row.min_acceptable_rr),
    allowedTradingDays: normalizeAllowedTradingDays(stringList(row.allowed_trading_days)),
    maxContractsPerTrade: numericFromDatabase(row.max_contracts_per_trade),
    maxWeeklyLoss: numericFromDatabase(row.max_weekly_loss),
    stopAfterDailyProfitTarget: booleanFromDatabase(row.stop_after_daily_profit_target),
    maxTradesPerDayScope: normalizeTradingRuleScope(
      row.max_trades_per_day_scope == null ? null : String(row.max_trades_per_day_scope)
    ),
    dailyLossLimitScope: normalizeTradingRuleScope(
      row.daily_loss_limit_scope == null ? null : String(row.daily_loss_limit_scope)
    ),
    dailyProfitRulesScope: normalizeTradingRuleScope(
      row.daily_profit_rules_scope == null ? null : String(row.daily_profit_rules_scope)
    ),
    maxWeeklyLossScope: normalizeTradingRuleScope(
      row.max_weekly_loss_scope == null ? null : String(row.max_weekly_loss_scope)
    ),
    updatedAt: row.updated_at == null ? null : String(row.updated_at),
  }
}

export function mapTradingPreferenceOverride(
  row: Record<string, unknown>
): TradingPreferenceAccountOverride {
  return {
    userId: String(row.user_id ?? ""),
    accountId: String(row.account_id ?? ""),
    overridesDailyLoss: row.overrides_daily_loss === true,
    dailyLossLimit: numericFromDatabase(row.daily_loss_limit),
    overridesDailyProfitTarget: row.overrides_daily_profit_target === true,
    dailyProfitTarget: numericFromDatabase(row.daily_profit_target),
    overridesMaxDrawdownGoal: row.overrides_max_drawdown_goal === true,
    maxDrawdownGoal: numericFromDatabase(row.max_drawdown_goal),
    updatedAt: row.updated_at == null ? null : String(row.updated_at),
  }
}

export function mapTradingPreferenceRevision(
  row: Record<string, unknown>
): TradingPreferenceRevision {
  return {
    id: String(row.id ?? ""),
    userId: String(row.user_id ?? ""),
    accountId: row.account_id == null ? null : String(row.account_id),
    effectiveFrom: String(row.effective_from ?? ""),
    tradingStyle: styleFromDatabase(row.trading_style),
    preferredSessions: normalizePreferenceSessions(stringList(row.preferred_sessions)),
    primaryInstruments: normalizePreferenceInstruments(stringList(row.primary_instruments)),
    targetRr: numericFromDatabase(row.target_rr),
    maxTradesPerDay: numericFromDatabase(row.max_trades_per_day),
    dailyLossLimit: numericFromDatabase(row.daily_loss_limit),
    consecutiveLossPause: numericFromDatabase(row.consecutive_loss_pause),
    breakevenTolerance: numericFromDatabase(row.breakeven_tolerance),
    dailyProfitTarget: numericFromDatabase(row.daily_profit_target),
    maxDrawdownGoal: numericFromDatabase(row.max_drawdown_goal),
    plannedStartMinute: numericFromDatabase(row.planned_start_minute),
    plannedEndMinute: numericFromDatabase(row.planned_end_minute),
    waitAfterLossMinutes: numericFromDatabase(row.wait_after_loss_minutes),
    maxRiskPerTrade: numericFromDatabase(row.max_risk_per_trade),
    minAcceptableRr: numericFromDatabase(row.min_acceptable_rr),
    allowedTradingDays: normalizeAllowedTradingDays(stringList(row.allowed_trading_days)),
    maxContractsPerTrade: numericFromDatabase(row.max_contracts_per_trade),
    maxWeeklyLoss: numericFromDatabase(row.max_weekly_loss),
    stopAfterDailyProfitTarget: booleanFromDatabase(row.stop_after_daily_profit_target),
    maxTradesPerDayScope: normalizeTradingRuleScope(
      row.max_trades_per_day_scope == null ? null : String(row.max_trades_per_day_scope)
    ),
    dailyLossLimitScope: normalizeTradingRuleScope(
      row.daily_loss_limit_scope == null ? null : String(row.daily_loss_limit_scope)
    ),
    dailyProfitRulesScope: normalizeTradingRuleScope(
      row.daily_profit_rules_scope == null ? null : String(row.daily_profit_rules_scope)
    ),
    maxWeeklyLossScope: normalizeTradingRuleScope(
      row.max_weekly_loss_scope == null ? null : String(row.max_weekly_loss_scope)
    ),
    overridesDailyLoss: row.overrides_daily_loss === true,
    overridesDailyProfitTarget: row.overrides_daily_profit_target === true,
    overridesMaxDrawdownGoal: row.overrides_max_drawdown_goal === true,
  }
}

export function globalToRow(prefs: TradingPreferenceGlobal): Record<string, unknown> {
  return {
    user_id: prefs.userId,
    trading_style: prefs.tradingStyle,
    preferred_sessions: prefs.preferredSessions,
    primary_instruments: prefs.primaryInstruments,
    target_rr: prefs.targetRr,
    max_trades_per_day: prefs.maxTradesPerDay,
    daily_loss_limit: prefs.dailyLossLimit,
    consecutive_loss_pause: prefs.consecutiveLossPause,
    breakeven_tolerance: prefs.breakevenTolerance,
    daily_profit_target: prefs.dailyProfitTarget,
    max_drawdown_goal: prefs.maxDrawdownGoal,
    planned_start_minute: prefs.plannedStartMinute,
    planned_end_minute: prefs.plannedEndMinute,
    wait_after_loss_minutes: prefs.waitAfterLossMinutes,
    max_risk_per_trade: prefs.maxRiskPerTrade,
    min_acceptable_rr: prefs.minAcceptableRr,
    allowed_trading_days: prefs.allowedTradingDays,
    max_contracts_per_trade: prefs.maxContractsPerTrade,
    max_weekly_loss: prefs.maxWeeklyLoss,
    stop_after_daily_profit_target: prefs.stopAfterDailyProfitTarget,
    max_trades_per_day_scope: prefs.maxTradesPerDayScope,
    daily_loss_limit_scope: prefs.dailyLossLimitScope,
    daily_profit_rules_scope: prefs.dailyProfitRulesScope,
    max_weekly_loss_scope: prefs.maxWeeklyLossScope,
  }
}

export function overrideToRow(
  prefs: TradingPreferenceAccountOverride
): Record<string, unknown> {
  return {
    user_id: prefs.userId,
    account_id: prefs.accountId,
    overrides_daily_loss: prefs.overridesDailyLoss,
    daily_loss_limit: prefs.overridesDailyLoss ? prefs.dailyLossLimit : null,
    overrides_daily_profit_target: prefs.overridesDailyProfitTarget,
    daily_profit_target: prefs.overridesDailyProfitTarget ? prefs.dailyProfitTarget : null,
    overrides_max_drawdown_goal: prefs.overridesMaxDrawdownGoal,
    max_drawdown_goal: prefs.overridesMaxDrawdownGoal ? prefs.maxDrawdownGoal : null,
  }
}

type Client = SupabaseClient

export async function fetchTradingPreferenceGlobal(
  client: Client,
  userId: string
): Promise<TradingPreferenceGlobal> {
  const { data, error } = await client
    .from("trading_preferences")
    .select(GLOBAL_SELECT)
    .eq("user_id", userId)
    .maybeSingle()
  if (error) throw error
  return mapTradingPreferenceGlobal(
    (data as Record<string, unknown> | null) ?? null,
    userId
  )
}

export async function saveTradingPreferenceGlobal(
  client: Client,
  prefs: TradingPreferenceGlobal
): Promise<TradingPreferenceGlobal> {
  const { data, error } = await client
    .from("trading_preferences")
    .upsert(globalToRow(prefs) as never, { onConflict: "user_id" })
    .select(GLOBAL_SELECT)
    .single()
  if (error) throw error
  const saved = mapTradingPreferenceGlobal(data as Record<string, unknown>, prefs.userId)
  invalidateTradingPreferenceBundle(prefs.userId)
  return saved
}

export async function fetchTradingPreferenceOverrides(
  client: Client,
  userId: string
): Promise<TradingPreferenceAccountOverride[]> {
  const { data, error } = await client
    .from("trading_preference_account_overrides")
    .select(OVERRIDE_SELECT)
    .eq("user_id", userId)
  if (error) throw error
  return ((data ?? []) as Record<string, unknown>[]).map(mapTradingPreferenceOverride)
}

export async function saveTradingPreferenceOverride(
  client: Client,
  prefs: TradingPreferenceAccountOverride
): Promise<TradingPreferenceAccountOverride> {
  const { data, error } = await client
    .from("trading_preference_account_overrides")
    .upsert(overrideToRow(prefs) as never, { onConflict: "user_id,account_id" })
    .select(OVERRIDE_SELECT)
    .single()
  if (error) throw error
  const saved = mapTradingPreferenceOverride(data as Record<string, unknown>)
  invalidateTradingPreferenceBundle(prefs.userId)
  return saved
}

export type TradingPreferenceBundle = {
  global: TradingPreferenceGlobal
  overrides: TradingPreferenceAccountOverride[]
  revisions: TradingPreferenceRevision[]
}

const preferenceBundles = createTradingPreferenceBundleCache<TradingPreferenceBundle>()

/** Drop the shared bundle so the next dashboard, scorecard, report, or psychology load refetches. */
export function invalidateTradingPreferenceBundle(userId: string) {
  preferenceBundles.invalidate(userId)
}

async function fetchTradingPreferenceBundle(
  client: Client,
  userId: string
): Promise<TradingPreferenceBundle> {
  const [global, overrides, revisions] = await Promise.all([
    fetchTradingPreferenceGlobal(client, userId),
    fetchTradingPreferenceOverrides(client, userId),
    fetchTradingPreferenceRevisions(client, userId),
  ])
  return { global, overrides, revisions }
}

/** Shared by Dashboard, Scorecard, Reports, and Psychology. */
export function loadTradingPreferenceBundle(
  client: Client,
  userId: string
): Promise<TradingPreferenceBundle> {
  return preferenceBundles.load(userId, () => fetchTradingPreferenceBundle(client, userId))
}

export async function fetchTradingPreferenceRevisions(
  client: Client,
  userId: string
): Promise<TradingPreferenceRevision[]> {
  const { data, error } = await client
    .from("trading_preference_revisions")
    .select(REVISION_SELECT)
    .eq("user_id", userId)
    .order("effective_from", { ascending: true })
  if (error) throw error
  return ((data ?? []) as Record<string, unknown>[]).map(mapTradingPreferenceRevision)
}
