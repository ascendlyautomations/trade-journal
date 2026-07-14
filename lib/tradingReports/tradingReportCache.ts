import { isDemoUserId } from "@/lib/demo/constants"
import { generateAllTradingReports } from "./generateTradingReport"
import { resolveNewTradingReportBadge } from "./tradingReportSeen"
import { requestTradingReportNotification } from "./tradingReportNotifications"
import type {
  NewTradingReportBadge,
  TradingReportPeriodKey,
  TradingReportsSnapshot,
} from "./tradingReportTypes"

const ALL_PERIOD_KEYS: TradingReportPeriodKey[] = [
  "weekly_this",
  "weekly_last",
  "monthly_this",
  "monthly_last",
]

type CacheEntry = {
  userId: string
  data: TradingReportsSnapshot
  invalidated: boolean
  loading: boolean
  tradeFingerprint: string
}

const reportsByUser = new Map<string, CacheEntry>()
const listeners = new Set<() => void>()
const notifiedPeriods = new Set<string>()
const badgeByUser = new Map<string, NewTradingReportBadge>()

function notify() {
  for (const listener of listeners) {
    listener()
  }
}

function tradeFingerprint(trades: any[]): string {
  if (!trades.length) return "0"
  const head = trades[0]?.id ?? ""
  const tail = trades[trades.length - 1]?.id ?? ""
  return `${trades.length}:${head}:${tail}`
}

export { tradeFingerprint as tradingReportsTradeFingerprint }

export function subscribeTradingReportsCache(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function invalidateTradingReportsCache(userId: string) {
  const entry = reportsByUser.get(userId)
  if (!entry) return
  reportsByUser.set(userId, { ...entry, invalidated: true })
  badgeByUser.delete(userId)
  notify()
}

export function getTradingReportsSnapshot(
  userId: string | null | undefined
): TradingReportsSnapshot | null {
  if (!userId) return null
  const entry = reportsByUser.get(userId)
  if (!entry || entry.invalidated || entry.loading) return null
  return entry.data
}

export function isTradingReportsLoading(userId: string | null | undefined): boolean {
  if (!userId) return false
  if (getTradingReportsSnapshot(userId)) return false
  return reportsByUser.get(userId)?.loading === true
}

export function getTradingReportFromSnapshot(
  userId: string | null | undefined,
  periodKey: TradingReportPeriodKey
) {
  return getTradingReportsSnapshot(userId)?.reports[periodKey] ?? null
}

export function getNewTradingReportBadge(
  userId: string | null | undefined
): NewTradingReportBadge {
  if (!userId) return null

  const snapshot = getTradingReportsSnapshot(userId)
  if (!snapshot) {
    badgeByUser.delete(userId)
    return null
  }

  const weeklyLastTrades = snapshot.reports.weekly_last.metrics.tradesTaken > 0
  const monthlyLastTrades = snapshot.reports.monthly_last.metrics.tradesTaken > 0

  const next = resolveNewTradingReportBadge(userId, {
    weeklyLast: weeklyLastTrades,
    monthlyLast: monthlyLastTrades,
  })

  const cached = badgeByUser.get(userId)
  if (cached === next) return cached

  if (next === null) {
    badgeByUser.delete(userId)
    return null
  }

  badgeByUser.set(userId, next)
  return next
}

function maybeQueueNotifications(userId: string, snapshot: TradingReportsSnapshot) {
  if (isDemoUserId(userId)) return

  for (const periodKey of ["weekly_last", "monthly_last"] as const) {
    const report = snapshot.reports[periodKey]
    if (report.metrics.tradesTaken === 0) continue

    const badge = resolveNewTradingReportBadge(userId, {
      weeklyLast: periodKey === "weekly_last",
      monthlyLast: periodKey === "monthly_last",
    })
    if (!badge) continue

    const notifyKey = `${userId}:${periodKey}:${report.periodStartIso}`
    if (notifiedPeriods.has(notifyKey)) continue
    notifiedPeriods.add(notifyKey)

    void requestTradingReportNotification({
      periodKey,
      kind: report.kind,
      title:
        report.kind === "weekly"
          ? "Your Weekly Trading Report is Ready"
          : "Your Monthly Trading Report is Ready",
    })
  }
}

export function ensureTradingReportsLoaded(
  trades: any[],
  userId: string | null | undefined,
  options: { force?: boolean } = {}
): TradingReportsSnapshot | null {
  if (!userId) return null

  const fingerprint = tradeFingerprint(trades)
  const existing = reportsByUser.get(userId)

  if (
    !options.force &&
    existing &&
    !existing.invalidated &&
    !existing.loading &&
    existing.tradeFingerprint === fingerprint &&
    existing.data
  ) {
    return existing.data
  }

  const snapshot: TradingReportsSnapshot = {
    reports: generateAllTradingReports(trades),
    computedAt: Date.now(),
  }

  reportsByUser.set(userId, {
    userId,
    data: snapshot,
    invalidated: false,
    loading: false,
    tradeFingerprint: fingerprint,
  })
  notify()

  maybeQueueNotifications(userId, snapshot)

  return snapshot
}

export function primeTradingReportsFromTrades(userId: string, trades: any[]) {
  if (!userId) return
  const snapshot: TradingReportsSnapshot = {
    reports: generateAllTradingReports(trades),
    computedAt: Date.now(),
  }
  reportsByUser.set(userId, {
    userId,
    data: snapshot,
    invalidated: false,
    loading: false,
    tradeFingerprint: tradeFingerprint(trades),
  })
  notify()
}

export { ALL_PERIOD_KEYS }
