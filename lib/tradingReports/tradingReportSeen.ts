import type {
  NewTradingReportBadge,
  TradingReportPeriodKey,
} from "./tradingReportTypes"
import {
  isMonthlyReportReleaseDay,
  isWeeklyReportReleaseDay,
  tradingReportPeriodId,
} from "./tradingReportPeriods"

const STORAGE_KEY = "tradetraxs_trading_reports_seen_v1"

/** Stable references for useSyncExternalStore getSnapshot (must not allocate per call). */
export const WEEKLY_TRADING_REPORT_BADGE: NewTradingReportBadge = {
  kind: "weekly",
  label: "🟢 New Weekly Report",
}

export const MONTHLY_TRADING_REPORT_BADGE: NewTradingReportBadge = {
  kind: "monthly",
  label: "🟣 Monthly Report Ready",
}

type SeenState = Partial<Record<TradingReportPeriodKey, string>>

function readSeenState(userId: string): SeenState {
  if (typeof window === "undefined") return {}
  try {
    const raw = window.localStorage.getItem(`${STORAGE_KEY}:${userId}`)
    if (!raw) return {}
    return JSON.parse(raw) as SeenState
  } catch {
    return {}
  }
}

function writeSeenState(userId: string, state: SeenState) {
  if (typeof window === "undefined") return
  try {
    window.localStorage.setItem(`${STORAGE_KEY}:${userId}`, JSON.stringify(state))
    window.dispatchEvent(new CustomEvent("tj-trading-reports-seen"))
  } catch {
    // ignore quota errors
  }
}

export function subscribeTradingReportSeen(listener: () => void): () => void {
  if (typeof window === "undefined") return () => {}
  const handler = () => listener()
  window.addEventListener("tj-trading-reports-seen", handler)
  return () => window.removeEventListener("tj-trading-reports-seen", handler)
}

export function markTradingReportSeen(
  userId: string,
  periodKey: TradingReportPeriodKey,
  now = new Date()
) {
  const state = readSeenState(userId)
  state[periodKey] = tradingReportPeriodId(periodKey, now)
  writeSeenState(userId, state)
}

export function isTradingReportUnread(
  userId: string,
  periodKey: TradingReportPeriodKey,
  now = new Date()
): boolean {
  const state = readSeenState(userId)
  const currentId = tradingReportPeriodId(periodKey, now)
  return state[periodKey] !== currentId
}

export function resolveNewTradingReportBadge(
  userId: string | null | undefined,
  hasTradesInPeriod: { weeklyLast: boolean; monthlyLast: boolean },
  now = new Date()
): NewTradingReportBadge {
  if (!userId) return null

  if (
    isWeeklyReportReleaseDay(now) &&
    hasTradesInPeriod.weeklyLast &&
    isTradingReportUnread(userId, "weekly_last", now)
  ) {
    return WEEKLY_TRADING_REPORT_BADGE
  }

  if (
    isMonthlyReportReleaseDay(now) &&
    hasTradesInPeriod.monthlyLast &&
    isTradingReportUnread(userId, "monthly_last", now)
  ) {
    return MONTHLY_TRADING_REPORT_BADGE
  }

  return null
}
