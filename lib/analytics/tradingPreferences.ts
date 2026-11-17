import {
  normalizeAllowedTradingDays,
  normalizeTradingRuleScope,
  type TradingRuleScope,
  type TradingRuleWeekday,
  TRADING_RULE_WEEKDAYS,
} from "@/lib/analytics/tradingRuleScope"
import { TRADING_SESSION_DISPLAY_ORDER } from "@/lib/tradingSession"

export {
  TRADING_RULE_SCOPE_OPTIONS,
  TRADING_RULE_WEEKDAYS,
  weekdayDisplayLabel,
  type TradingRuleScope,
  type TradingRuleWeekday,
} from "@/lib/analytics/tradingRuleScope"

/**
 * Optional trading-analytics preferences.
 *
 * A null field means that rule is off. Do not substitute a trading style,
 * a starter trade cap, or a personal breakeven band when the answer is blank.
 * Phase 3 analytics engines should call these helpers. They do not change
 * dashboard, scorecard, psychology, or report copy on their own.
 */

export const TRADING_STYLE_OPTIONS = [
  {
    id: "scalper",
    label: "Scalper",
    description: "Many short trades inside a session.",
  },
  {
    id: "day_trader",
    label: "Day Trader",
    description: "Trades opened and closed on the same day.",
  },
  {
    id: "swing_trader",
    label: "Swing Trader",
    description: "Trades held beyond the session.",
  },
] as const

export type TradingStyleId = (typeof TRADING_STYLE_OPTIONS)[number]["id"]

export const TRADING_PREFERENCE_SESSIONS = TRADING_SESSION_DISPLAY_ORDER

export type TradingPreferenceSession =
  (typeof TRADING_PREFERENCE_SESSIONS)[number]

export type TradingPreferenceGlobal = {
  userId: string
  tradingStyle: TradingStyleId | null
  preferredSessions: TradingPreferenceSession[]
  primaryInstruments: string[]
  targetRr: number | null
  maxTradesPerDay: number | null
  dailyLossLimit: number | null
  consecutiveLossPause: number | null
  breakevenTolerance: number | null
  dailyProfitTarget: number | null
  maxDrawdownGoal: number | null
  plannedStartMinute: number | null
  plannedEndMinute: number | null
  waitAfterLossMinutes: number | null
  maxRiskPerTrade: number | null
  minAcceptableRr: number | null
  allowedTradingDays: TradingRuleWeekday[]
  maxContractsPerTrade: number | null
  maxWeeklyLoss: number | null
  stopAfterDailyProfitTarget: boolean
  maxTradesPerDayScope: TradingRuleScope
  dailyLossLimitScope: TradingRuleScope
  dailyProfitRulesScope: TradingRuleScope
  maxWeeklyLossScope: TradingRuleScope
  updatedAt: string | null
}

export type TradingPreferenceAccountOverride = {
  userId: string
  accountId: string
  overridesDailyLoss: boolean
  dailyLossLimit: number | null
  overridesDailyProfitTarget: boolean
  dailyProfitTarget: number | null
  overridesMaxDrawdownGoal: boolean
  maxDrawdownGoal: number | null
  updatedAt: string | null
}

export type TradingPreferenceRevision = {
  id: string
  userId: string
  accountId: string | null
  effectiveFrom: string
  tradingStyle: TradingStyleId | null
  preferredSessions: TradingPreferenceSession[]
  primaryInstruments: string[]
  targetRr: number | null
  maxTradesPerDay: number | null
  dailyLossLimit: number | null
  consecutiveLossPause: number | null
  breakevenTolerance: number | null
  dailyProfitTarget: number | null
  maxDrawdownGoal: number | null
  plannedStartMinute: number | null
  plannedEndMinute: number | null
  waitAfterLossMinutes: number | null
  maxRiskPerTrade: number | null
  minAcceptableRr: number | null
  allowedTradingDays: TradingRuleWeekday[]
  maxContractsPerTrade: number | null
  maxWeeklyLoss: number | null
  stopAfterDailyProfitTarget: boolean
  maxTradesPerDayScope: TradingRuleScope
  dailyLossLimitScope: TradingRuleScope
  dailyProfitRulesScope: TradingRuleScope
  maxWeeklyLossScope: TradingRuleScope
  overridesDailyLoss: boolean
  overridesDailyProfitTarget: boolean
  overridesMaxDrawdownGoal: boolean
}

/** Rules an analytics engine can read. Null means the rule is off. */
export type ResolvedTradingPreferences = {
  tradingStyle: TradingStyleId | null
  preferredSessions: TradingPreferenceSession[]
  primaryInstruments: string[]
  targetRr: number | null
  maxTradesPerDay: number | null
  dailyLossLimit: number | null
  consecutiveLossPause: number | null
  /** Null keeps the existing exact-$0 breakeven. A number is a ± dollar band. */
  breakevenTolerance: number | null
  dailyProfitTarget: number | null
  maxDrawdownGoal: number | null
  plannedHours: { startMinute: number; endMinute: number } | null
  waitAfterLossMinutes: number | null
  maxRiskPerTrade: number | null
  minAcceptableRr: number | null
  allowedTradingDays: TradingRuleWeekday[]
  maxContractsPerTrade: number | null
  maxWeeklyLoss: number | null
  stopAfterDailyProfitTarget: boolean
  maxTradesPerDayScope: TradingRuleScope
  dailyLossLimitScope: TradingRuleScope
  dailyProfitRulesScope: TradingRuleScope
  maxWeeklyLossScope: TradingRuleScope
  source: "unset" | "global" | "account"
}

export function emptyResolvedTradingPreferences(): ResolvedTradingPreferences {
  return {
    tradingStyle: null,
    preferredSessions: [],
    primaryInstruments: [],
    targetRr: null,
    maxTradesPerDay: null,
    dailyLossLimit: null,
    consecutiveLossPause: null,
    breakevenTolerance: null,
    dailyProfitTarget: null,
    maxDrawdownGoal: null,
    plannedHours: null,
    waitAfterLossMinutes: null,
    maxRiskPerTrade: null,
    minAcceptableRr: null,
    allowedTradingDays: [],
    maxContractsPerTrade: null,
    maxWeeklyLoss: null,
    stopAfterDailyProfitTarget: false,
    maxTradesPerDayScope: "combined",
    dailyLossLimitScope: "combined",
    dailyProfitRulesScope: "combined",
    maxWeeklyLossScope: "combined",
    source: "unset",
  }
}

export function emptyTradingPreferenceGlobal(userId: string): TradingPreferenceGlobal {
  return {
    userId,
    tradingStyle: null,
    preferredSessions: [],
    primaryInstruments: [],
    targetRr: null,
    maxTradesPerDay: null,
    dailyLossLimit: null,
    consecutiveLossPause: null,
    breakevenTolerance: null,
    dailyProfitTarget: null,
    maxDrawdownGoal: null,
    plannedStartMinute: null,
    plannedEndMinute: null,
    waitAfterLossMinutes: null,
    maxRiskPerTrade: null,
    minAcceptableRr: null,
    allowedTradingDays: [],
    maxContractsPerTrade: null,
    maxWeeklyLoss: null,
    stopAfterDailyProfitTarget: false,
    maxTradesPerDayScope: "combined",
    dailyLossLimitScope: "combined",
    dailyProfitRulesScope: "combined",
    maxWeeklyLossScope: "combined",
    updatedAt: null,
  }
}

function plannedHours(
  startMinute: number | null,
  endMinute: number | null
): { startMinute: number; endMinute: number } | null {
  if (startMinute == null || endMinute == null) return null
  if (startMinute === endMinute) return null
  return { startMinute, endMinute }
}

function moneyLimit(
  overrides: boolean,
  overrideAmount: number | null,
  globalAmount: number | null
): number | null {
  if (!overrides) return globalAmount
  return overrideAmount
}

/**
 * Current rules for a user, with an optional account overlay for dollar limits.
 * Style, sessions, instruments, and non-dollar rules always come from the global row.
 */
export function resolveTradingPreferences(
  global: TradingPreferenceGlobal | null,
  account: TradingPreferenceAccountOverride | null = null
): ResolvedTradingPreferences {
  if (!global && !account) return emptyResolvedTradingPreferences()

  const base = global
  const usesAccount =
    account != null &&
    (account.overridesDailyLoss ||
      account.overridesDailyProfitTarget ||
      account.overridesMaxDrawdownGoal)

  const resolvedDailyProfitTarget = moneyLimit(
    account?.overridesDailyProfitTarget ?? false,
    account?.dailyProfitTarget ?? null,
    base?.dailyProfitTarget ?? null
  )

  return {
    tradingStyle: base?.tradingStyle ?? null,
    preferredSessions: base?.preferredSessions ?? [],
    primaryInstruments: base?.primaryInstruments ?? [],
    targetRr: base?.targetRr ?? null,
    maxTradesPerDay: base?.maxTradesPerDay ?? null,
    dailyLossLimit: moneyLimit(
      account?.overridesDailyLoss ?? false,
      account?.dailyLossLimit ?? null,
      base?.dailyLossLimit ?? null
    ),
    consecutiveLossPause: base?.consecutiveLossPause ?? null,
    breakevenTolerance: base?.breakevenTolerance ?? null,
    dailyProfitTarget: resolvedDailyProfitTarget,
    maxDrawdownGoal: moneyLimit(
      account?.overridesMaxDrawdownGoal ?? false,
      account?.maxDrawdownGoal ?? null,
      base?.maxDrawdownGoal ?? null
    ),
    plannedHours: plannedHours(
      base?.plannedStartMinute ?? null,
      base?.plannedEndMinute ?? null
    ),
    waitAfterLossMinutes: base?.waitAfterLossMinutes ?? null,
    maxRiskPerTrade: base?.maxRiskPerTrade ?? null,
    minAcceptableRr: base?.minAcceptableRr ?? null,
    allowedTradingDays: base?.allowedTradingDays ?? [],
    maxContractsPerTrade: base?.maxContractsPerTrade ?? null,
    maxWeeklyLoss: base?.maxWeeklyLoss ?? null,
    stopAfterDailyProfitTarget:
      (base?.stopAfterDailyProfitTarget ?? false) && resolvedDailyProfitTarget != null,
    maxTradesPerDayScope: normalizeTradingRuleScope(base?.maxTradesPerDayScope),
    dailyLossLimitScope: normalizeTradingRuleScope(base?.dailyLossLimitScope),
    dailyProfitRulesScope: normalizeTradingRuleScope(base?.dailyProfitRulesScope),
    maxWeeklyLossScope: normalizeTradingRuleScope(base?.maxWeeklyLossScope),
    source: usesAccount ? "account" : base ? "global" : "unset",
  }
}

function revisionToGlobal(row: TradingPreferenceRevision): TradingPreferenceGlobal {
  return {
    userId: row.userId,
    tradingStyle: row.tradingStyle,
    preferredSessions: row.preferredSessions,
    primaryInstruments: row.primaryInstruments,
    targetRr: row.targetRr,
    maxTradesPerDay: row.maxTradesPerDay,
    dailyLossLimit: row.dailyLossLimit,
    consecutiveLossPause: row.consecutiveLossPause,
    breakevenTolerance: row.breakevenTolerance,
    dailyProfitTarget: row.dailyProfitTarget,
    maxDrawdownGoal: row.maxDrawdownGoal,
    plannedStartMinute: row.plannedStartMinute,
    plannedEndMinute: row.plannedEndMinute,
    waitAfterLossMinutes: row.waitAfterLossMinutes,
    maxRiskPerTrade: row.maxRiskPerTrade,
    minAcceptableRr: row.minAcceptableRr,
    allowedTradingDays: row.allowedTradingDays,
    maxContractsPerTrade: row.maxContractsPerTrade,
    maxWeeklyLoss: row.maxWeeklyLoss,
    stopAfterDailyProfitTarget: row.stopAfterDailyProfitTarget,
    maxTradesPerDayScope: row.maxTradesPerDayScope,
    dailyLossLimitScope: row.dailyLossLimitScope,
    dailyProfitRulesScope: row.dailyProfitRulesScope,
    maxWeeklyLossScope: row.maxWeeklyLossScope,
    updatedAt: row.effectiveFrom,
  }
}

function revisionToOverride(
  row: TradingPreferenceRevision
): TradingPreferenceAccountOverride | null {
  if (!row.accountId) return null
  return {
    userId: row.userId,
    accountId: row.accountId,
    overridesDailyLoss: row.overridesDailyLoss,
    dailyLossLimit: row.dailyLossLimit,
    overridesDailyProfitTarget: row.overridesDailyProfitTarget,
    dailyProfitTarget: row.dailyProfitTarget,
    overridesMaxDrawdownGoal: row.overridesMaxDrawdownGoal,
    maxDrawdownGoal: row.maxDrawdownGoal,
    updatedAt: row.effectiveFrom,
  }
}

function latestAt(
  rows: TradingPreferenceRevision[],
  atMs: number
): TradingPreferenceRevision | null {
  let best: TradingPreferenceRevision | null = null
  let bestMs = -Infinity
  for (const row of rows) {
    const ms = Date.parse(row.effectiveFrom)
    if (!Number.isFinite(ms) || ms > atMs || ms < bestMs) continue
    best = row
    bestMs = ms
  }
  return best
}

/**
 * Rules that were saved at `at`. A trade before the first save has no personal rule.
 * Dollar limits use the account snapshot when one exists, otherwise the global snapshot.
 */
export function tradingPreferencesActiveAt(
  revisions: readonly TradingPreferenceRevision[],
  at: Date,
  accountId?: string | null
): ResolvedTradingPreferences {
  const atMs = at.getTime()
  const global = latestAt(
    revisions.filter((row) => row.accountId == null),
    atMs
  )
  const account = accountId
    ? latestAt(
        revisions.filter((row) => row.accountId === accountId),
        atMs
      )
    : null
  return resolveTradingPreferences(
    global ? revisionToGlobal(global) : null,
    account ? revisionToOverride(account) : null
  )
}

export function isTradingStyleId(value: string | null | undefined): value is TradingStyleId {
  return TRADING_STYLE_OPTIONS.some((option) => option.id === value)
}

export function normalizePreferenceSessions(
  values: readonly string[] | null | undefined
): TradingPreferenceSession[] {
  const allowed = new Set<string>(TRADING_PREFERENCE_SESSIONS)
  const seen = new Set<string>()
  const next: TradingPreferenceSession[] = []
  for (const value of values ?? []) {
    const label = value.trim()
    if (!allowed.has(label) || seen.has(label)) continue
    seen.add(label)
    next.push(label as TradingPreferenceSession)
  }
  return TRADING_PREFERENCE_SESSIONS.filter((label) => seen.has(label))
}

export function normalizePreferenceInstruments(
  values: readonly string[] | null | undefined
): string[] {
  const seen = new Set<string>()
  const next: string[] = []
  for (const value of values ?? []) {
    const symbol = value.trim().toUpperCase().replace(/\s+/g, "")
    if (!/^[A-Z0-9./-]{1,16}$/.test(symbol) || seen.has(symbol)) continue
    seen.add(symbol)
    next.push(symbol)
    if (next.length === 12) break
  }
  return next
}

export function parseOptionalPositive(raw: string): number | null | "invalid" {
  const trimmed = raw.trim()
  if (!trimmed) return null
  const value = Number(trimmed)
  if (!Number.isFinite(value) || value <= 0) return "invalid"
  return value
}

export function parseOptionalNonNegative(raw: string): number | null | "invalid" {
  const trimmed = raw.trim()
  if (!trimmed) return null
  const value = Number(trimmed)
  if (!Number.isFinite(value) || value < 0) return "invalid"
  return value
}

export function parseOptionalInteger(
  raw: string,
  min: number,
  max: number
): number | null | "invalid" {
  const trimmed = raw.trim()
  if (!trimmed) return null
  const value = Number(trimmed)
  if (!Number.isInteger(value) || value < min || value > max) return "invalid"
  return value
}

export function minutesToTimeInput(minutes: number | null): string {
  if (minutes == null) return ""
  const hour = Math.floor(minutes / 60)
  const minute = minutes % 60
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`
}

export function timeInputToMinutes(raw: string): number | null | "invalid" {
  const trimmed = raw.trim()
  if (!trimmed) return null
  const match = /^(\d{2}):(\d{2})$/.exec(trimmed)
  if (!match) return "invalid"
  const hour = Number(match[1])
  const minute = Number(match[2])
  if (hour > 23 || minute > 59) return "invalid"
  return hour * 60 + minute
}

export function formatMinuteLabel(minutes: number): string {
  const hour24 = Math.floor(minutes / 60)
  const minute = minutes % 60
  const suffix = hour24 >= 12 ? "PM" : "AM"
  const hour = hour24 % 12 === 0 ? 12 : hour24 % 12
  return `${hour}:${String(minute).padStart(2, "0")} ${suffix} ET`
}

export function numericFromDatabase(value: unknown): number | null {
  if (value == null || value === "") return null
  const parsed = typeof value === "number" ? value : Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

export function booleanFromDatabase(value: unknown): boolean {
  return value === true
}

export { normalizeAllowedTradingDays, normalizeTradingRuleScope }
