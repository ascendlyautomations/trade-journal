import { checkInDateKey } from "@/lib/dailyCheckIn/dateKey"

export const TRADING_RULE_SCOPE_OPTIONS = [
  { id: "combined", label: "All Accounts Combined" },
  { id: "per_account", label: "Per Account" },
] as const

export type TradingRuleScope = (typeof TRADING_RULE_SCOPE_OPTIONS)[number]["id"]

export const TRADING_RULE_WEEKDAYS = [
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
  "sunday",
] as const

export type TradingRuleWeekday = (typeof TRADING_RULE_WEEKDAYS)[number]

const WEEKDAY_ORDER: readonly TradingRuleWeekday[] = TRADING_RULE_WEEKDAYS

export function isTradingRuleScope(value: string | null | undefined): value is TradingRuleScope {
  return value === "combined" || value === "per_account"
}

export function normalizeTradingRuleScope(
  value: string | null | undefined
): TradingRuleScope {
  return isTradingRuleScope(value) ? value : "combined"
}

export function scopeBucketLabel(scope: TradingRuleScope): string {
  return scope === "per_account" ? "per account" : "all accounts combined"
}

export function scopedDayBucket(
  dayKey: string,
  accountId: string | null,
  scope: TradingRuleScope
): string {
  if (scope === "per_account") {
    return `${dayKey}::${accountId ?? "unassigned"}`
  }
  return dayKey
}

export function scopedWeekBucket(
  weekKey: string,
  accountId: string | null,
  scope: TradingRuleScope
): string {
  if (scope === "per_account") {
    return `${weekKey}::${accountId ?? "unassigned"}`
  }
  return weekKey
}

export function easternWeekdayFromInstant(at: Date): TradingRuleWeekday | null {
  if (Number.isNaN(at.getTime())) return null
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    weekday: "long",
  }).formatToParts(at)
  const raw = parts.find((part) => part.type === "weekday")?.value.toLowerCase()
  if (!raw) return null
  return TRADING_RULE_WEEKDAYS.find((day) => day === raw) ?? null
}

export function easternWeekKeyFromInstant(at: Date): string | null {
  const dayKey = checkInDateKey(at)
  if (!dayKey) return null
  return easternWeekKeyFromDayKey(dayKey, at)
}

/** Monday-start Eastern week label `YYYY-MM-DD` for the week's Monday. */
export function easternWeekKeyFromDayKey(dayKey: string, at: Date): string | null {
  const weekday = easternWeekdayFromInstant(at)
  if (!weekday) return null
  const index = WEEKDAY_ORDER.indexOf(weekday)
  if (index < 0) return null
  const [y, m, d] = dayKey.split("-").map((part) => Number(part))
  if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) return null
  const utc = Date.UTC(y, m - 1, d)
  const mondayOffset = index
  const mondayUtc = utc - mondayOffset * 86_400_000
  const monday = new Date(mondayUtc)
  return `${monday.getUTCFullYear()}-${String(monday.getUTCMonth() + 1).padStart(2, "0")}-${String(monday.getUTCDate()).padStart(2, "0")}`
}

export function normalizeAllowedTradingDays(
  values: readonly string[] | null | undefined
): TradingRuleWeekday[] {
  const seen = new Set<string>()
  const next: TradingRuleWeekday[] = []
  for (const value of values ?? []) {
    const day = value.trim().toLowerCase()
    if (!TRADING_RULE_WEEKDAYS.includes(day as TradingRuleWeekday) || seen.has(day)) continue
    seen.add(day)
    next.push(day as TradingRuleWeekday)
  }
  return WEEKDAY_ORDER.filter((day) => seen.has(day))
}

export function weekdayDisplayLabel(day: TradingRuleWeekday): string {
  return day.charAt(0).toUpperCase() + day.slice(1)
}
