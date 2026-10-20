import type { ManualPayoutLedgerEntry } from "@/lib/accountPayoutEntry"
import { supportsLiveWithdrawal } from "@/lib/accountPayoutPolicy"
import { ledgerTrackedBalance } from "@/lib/accountPayoutEntry"
import { getTradingDayKey } from "@/lib/formatDate"
import { parseAccountSizeToNumber } from "@/lib/propfirmMetrics"
import { isCopyGroupFilterValue } from "@/lib/tradeAccountSelection"
import {
  getDashboardTradingDayKey,
  resolveDashboardTradeDate,
  tradeMatchesDashboardSelectedDate,
  tradeMatchesDashboardTimeFilter,
  type DashboardTradeDateFields,
} from "@/lib/dashboardTradeDate"
import { excludeBacktestTrades } from "@/lib/tradeModeFilters"

export type DashboardEquityChartPoint = {
  date: string
  equity: number
}

export type DashboardLiveAccountSource = {
  category?: unknown
  mode?: unknown
  account_size?: unknown
  max_drawdown?: unknown
  drawdown_type?: unknown
}

function accountIdFromDashboardAccountFilterKey(
  accountFilter: string | undefined
): string | null {
  if (!accountFilter || accountFilter === "all") return null
  const segments = accountFilter.split("|")
  const id = segments[segments.length - 1]?.trim()
  return id || null
}

/** Single selected Live manual-ledger account (not Prop Firm eval/funded snapshot). */
export function resolveDashboardLiveSingleAccountId(options: {
  userId: string | null | undefined
  accountFilter: string
  accountById: Record<string, DashboardLiveAccountSource | null | undefined>
  propFirmAccountId: string | null | undefined
}): string | null {
  const { userId, accountFilter, accountById, propFirmAccountId } = options
  if (!userId) return null
  if (accountFilter === "all" || isCopyGroupFilterValue(accountFilter)) {
    return null
  }
  const id = accountIdFromDashboardAccountFilterKey(accountFilter)
  if (!id) return null
  if (propFirmAccountId && propFirmAccountId === id) return null
  const account = accountById[id]
  if (!account || !supportsLiveWithdrawal(account)) return null
  return id
}

export function parsePersonalDrawdownLimit(
  value: number | null | undefined
): number | null {
  if (value == null || !Number.isFinite(value) || value <= 0) return null
  return value
}

/** Max drawdown reference on live account balance equity (starting balance − limit). */
export function computePersonalDrawdownLimitBalanceLineY(
  account: { account_size?: unknown },
  drawdownLimit: number
): number {
  const startingBalance = parseAccountSizeToNumber(account)
  return startingBalance - drawdownLimit
}

export function formatDashboardEquityCurvePointDate(
  trade: DashboardTradeDateFields
): string {
  const resolved = resolveDashboardTradeDate(trade)
  if (resolved) return resolved.toISOString()

  const raw = trade.created_at ?? trade.date
  if (raw != null) {
    const parsed = new Date(String(raw).trim())
    if (!Number.isNaN(parsed.getTime())) return parsed.toISOString()
  }
  return ""
}

export type DashboardEquityPeriodContext = {
  timeFilter: string
  selectedDate: string
  customRangeStart: string
  customRangeEnd: string
  now?: Date
}

function pad2(n: number) {
  return String(n).padStart(2, "0")
}

function addCalendarDays(y: number, m: number, d: number, delta: number) {
  const utc = Date.UTC(y, m - 1, d + delta)
  const nd = new Date(utc)
  return {
    y: nd.getUTCFullYear(),
    m: nd.getUTCMonth() + 1,
    d: nd.getUTCDate(),
  }
}

/** Session open for a futures trading-day key (18:00 ET prior calendar day). */
function tradingDayKeySessionStartMs(dayKey: string): number | null {
  const parts = dayKey.trim().split("-").map(Number)
  if (parts.length !== 3 || parts.some((n) => !Number.isFinite(n))) return null
  const [y, m, d] = parts
  const prev = addCalendarDays(y, m, d, -1)
  const iso = `${prev.y}-${pad2(prev.m)}-${pad2(prev.d)}T18:00:00`
  const parsed = new Date(iso)
  return Number.isNaN(parsed.getTime()) ? null : parsed.getTime()
}

export function resolveDashboardPeriodStartMs(
  context: DashboardEquityPeriodContext
): number | null {
  const now = context.now ?? new Date()
  if (context.selectedDate.trim()) {
    return tradingDayKeySessionStartMs(context.selectedDate.trim())
  }
  switch (context.timeFilter) {
    case "all":
      return null
    case "daily": {
      const start = new Date(now)
      start.setHours(0, 0, 0, 0)
      return start.getTime()
    }
    case "weekly": {
      const start = new Date(now)
      start.setDate(now.getDate() - 7)
      return start.getTime()
    }
    case "monthly": {
      return new Date(now.getFullYear(), now.getMonth(), 1).getTime()
    }
    case "yearly": {
      return new Date(now.getFullYear(), 0, 1).getTime()
    }
    case "custom": {
      if (
        !context.customRangeStart.trim() ||
        !context.customRangeEnd.trim()
      ) {
        return null
      }
      return new Date(`${context.customRangeStart.trim()}T00:00:00`).getTime()
    }
    default:
      return null
  }
}

export function resolveDashboardPeriodEndMs(
  context: DashboardEquityPeriodContext
): number {
  const now = context.now ?? new Date()
  if (context.selectedDate.trim()) {
    const start = tradingDayKeySessionStartMs(context.selectedDate.trim())
    if (start != null) return start + 24 * 60 * 60 * 1000
  }
  if (context.timeFilter === "custom" && context.customRangeEnd.trim()) {
    return new Date(
      `${context.customRangeEnd.trim()}T23:59:59.999`
    ).getTime()
  }
  return now.getTime()
}

function payoutDateToSortMs(payoutDate: string): number | null {
  const d = payoutDate.trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return null
  const parsed = new Date(`${d}T12:00:00`)
  return Number.isNaN(parsed.getTime()) ? null : parsed.getTime()
}

function withdrawalMatchesDashboardPeriod(
  payoutDate: string,
  context: DashboardEquityPeriodContext
): boolean {
  const d = payoutDate.trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return false
  const now = context.now ?? new Date()

  if (context.selectedDate.trim()) {
    const key = getTradingDayKey(`${d}T12:00:00`)
    return key === context.selectedDate.trim()
  }

  if (context.timeFilter === "all") return true

  const instant = new Date(`${d}T12:00:00`)
  if (context.timeFilter === "daily") {
    return instant.toDateString() === now.toDateString()
  }
  if (context.timeFilter === "weekly") {
    const weekAgo = new Date(now)
    weekAgo.setDate(now.getDate() - 7)
    return instant >= weekAgo
  }
  if (context.timeFilter === "monthly") {
    return (
      instant.getMonth() === now.getMonth() &&
      instant.getFullYear() === now.getFullYear()
    )
  }
  if (context.timeFilter === "yearly") {
    return instant.getFullYear() === now.getFullYear()
  }
  if (context.timeFilter === "custom") {
    if (!context.customRangeStart.trim() || !context.customRangeEnd.trim()) {
      return true
    }
    const start = new Date(`${context.customRangeStart.trim()}T00:00:00`)
    const end = new Date(`${context.customRangeEnd.trim()}T23:59:59.999`)
    return instant >= start && instant <= end
  }
  return true
}

type LiveEquityEvent = {
  sortMs: number
  date: string
  delta: number
  kind: "trade" | "withdrawal"
}

function tradeIsBeforePeriod(
  trade: DashboardTradeDateFields,
  periodStartMs: number | null,
  selectedDate: string
): boolean {
  if (selectedDate.trim()) {
    const key = getDashboardTradingDayKey(trade)
    if (!key) return false
    return key < selectedDate.trim()
  }
  if (periodStartMs == null) return false
  const tradeMs = resolveDashboardTradeDate(trade)?.getTime()
  if (tradeMs == null) return false
  return tradeMs < periodStartMs
}

function withdrawalIsBeforePeriod(
  payoutDate: string,
  periodStartMs: number | null,
  selectedDate: string
): boolean {
  const d = payoutDate.trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return false
  if (selectedDate.trim()) {
    const key = getTradingDayKey(`${d}T12:00:00`)
    if (!key) return false
    return key < selectedDate.trim()
  }
  if (periodStartMs == null) return false
  const ms = payoutDateToSortMs(d)
  return ms != null && ms < periodStartMs
}

/**
 * Live single-account equity curve (account balance), aligned with ledger hero value.
 */
function tradeMatchesDashboardPeriod(
  trade: DashboardTradeDateFields,
  period: DashboardEquityPeriodContext
): boolean {
  const now = period.now ?? new Date()
  if (
    period.selectedDate.trim() &&
    !tradeMatchesDashboardSelectedDate(trade, period.selectedDate)
  ) {
    return false
  }
  return tradeMatchesDashboardTimeFilter(
    trade,
    period.timeFilter,
    now,
    period.customRangeStart,
    period.customRangeEnd
  )
}

export function computeLiveAccountEquityChartData(options: {
  account: { account_size?: unknown }
  accountId: string
  lifetimeTrades: readonly ({ account_id?: unknown; pnl?: unknown } & DashboardTradeDateFields)[]
  ledgerEntries: readonly ManualPayoutLedgerEntry[]
  period: DashboardEquityPeriodContext
}): DashboardEquityChartPoint[] {
  const { account, accountId, lifetimeTrades, ledgerEntries, period } =
    options
  const id = String(accountId).trim()
  const startingBalance = parseAccountSizeToNumber(account)
  const periodStartMs = resolveDashboardPeriodStartMs(period)
  const periodEndMs = resolveDashboardPeriodEndMs(period)
  const hasPeriodWindow =
    periodStartMs != null || period.selectedDate.trim().length > 0

  const lifetimeForAccount = excludeBacktestTrades([...lifetimeTrades]).filter(
    (t) => String(t.account_id ?? "").trim() === id
  )

  let openingBalance = startingBalance
  for (const trade of lifetimeForAccount) {
    if (
      tradeIsBeforePeriod(trade, periodStartMs, period.selectedDate)
    ) {
      openingBalance += Number(trade.pnl) || 0
    }
  }
  for (const entry of ledgerEntries) {
    if (
      withdrawalIsBeforePeriod(
        entry.payout_date,
        periodStartMs,
        period.selectedDate
      )
    ) {
      openingBalance -= Number(entry.amount) || 0
    }
  }

  const inPeriodEvents: LiveEquityEvent[] = []

  for (const trade of lifetimeForAccount) {
    if (!tradeMatchesDashboardPeriod(trade, period)) continue
    const sortMs = resolveDashboardTradeDate(trade)?.getTime()
    if (sortMs == null) continue
    const date = formatDashboardEquityCurvePointDate(trade)
    if (!date) continue
    inPeriodEvents.push({
      sortMs,
      date,
      delta: Number(trade.pnl) || 0,
      kind: "trade",
    })
  }

  for (const entry of ledgerEntries) {
    if (!withdrawalMatchesDashboardPeriod(entry.payout_date, period)) continue
    const sortMs = payoutDateToSortMs(entry.payout_date)
    if (sortMs == null) continue
    inPeriodEvents.push({
      sortMs,
      date: new Date(sortMs).toISOString(),
      delta: -(Number(entry.amount) || 0),
      kind: "withdrawal",
    })
  }

  inPeriodEvents.sort((a, b) => {
    if (a.sortMs !== b.sortMs) return a.sortMs - b.sortMs
    if (a.kind === b.kind) return 0
    return a.kind === "trade" ? -1 : 1
  })

  const points: DashboardEquityChartPoint[] = []

  if (hasPeriodWindow) {
    const anchorMs = periodStartMs ?? periodEndMs
    points.push({
      date: new Date(anchorMs).toISOString(),
      equity: openingBalance,
    })
  }

  if (inPeriodEvents.length === 0) {
    if (hasPeriodWindow) {
      points.push({
        date: new Date(periodEndMs).toISOString(),
        equity: openingBalance,
      })
    } else {
      points.push({
        date: new Date().toISOString(),
        equity: startingBalance,
      })
    }
    return points
  }

  if (!hasPeriodWindow) {
    const first = inPeriodEvents[0]
    points.push({ date: first.date, equity: startingBalance })
  }

  let balance = openingBalance
  for (const event of inPeriodEvents) {
    balance += event.delta
    points.push({ date: event.date, equity: balance })
  }

  return points
}

export function sumLifetimeRealizedPnLForAccount(
  trades: readonly { account_id?: unknown; pnl?: unknown }[],
  accountId: string
): number {
  const id = String(accountId).trim()
  if (!id) return 0
  return excludeBacktestTrades([...trades])
    .filter((trade) => String(trade.account_id ?? "").trim() === id)
    .reduce((sum, trade) => sum + (Number(trade.pnl) || 0), 0)
}

export function computeLiveLedgerAccountValue(
  account: { account_size?: unknown },
  trades: readonly { account_id?: unknown; pnl?: unknown }[],
  accountId: string,
  ledgerEntries: ReadonlyArray<{ amount: number }>
): number {
  const startingBalance = parseAccountSizeToNumber(account)
  const lifetimeRealizedPnL = sumLifetimeRealizedPnLForAccount(trades, accountId)
  return ledgerTrackedBalance(
    startingBalance,
    lifetimeRealizedPnL,
    ledgerEntries,
    0
  )
}
