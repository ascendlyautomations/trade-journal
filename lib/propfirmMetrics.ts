/**
 * PropFirm Mode calculation helpers.
 * Extracted from the analytics page for testability and reuse.
 */

import { getTradingDayKey } from "./formatDate.ts"

export type PropfirmTrade = {
  id?: string | null
  pnl?: number | string | null
  date?: string | null
  trade_date?: string | null
  entry_time?: string | null
  created_at?: string | null
}

export type PropfirmAccountRules = {
  account_size?: unknown
  consistency?: number | string | null
  max_drawdown?: number | string | null
  profit_target?: number | string | null
}

export type TrailingDrawdownResult = {
  currentBalance: number
  peakBalance: number
  drawdownFloor: number
  distanceToDD: number
  /** Largest (peak - balance) observed after any trade (for "max DD used" vs limit). */
  maxDrawdownUsed: number
  /** True if at any point after a trade, balance fell below the trailing drawdown floor. */
  breachedTrailingDD: boolean
}

export type ConsistencyRuleResult = {
  biggestWin: number
  totalProfit: number
  allowedMax: number
  isConsistent: boolean
  ruleActive: boolean
}

export type DailyMetricsResult = {
  dailyPnLMap: Record<string, number>
  dailyRows: [string, number][]
  winningDays: number
  todayPnL: number
  worstDay: number
  worstDailyLossUsed: number
}

export type PropfirmProgressResult = {
  totalPnL: number
  progressPercent: number
  isPassed: boolean
  isFailed: boolean
  status: "PASSED" | "FAILED" | "IN PROGRESS"
  ddPercent: number
  distanceDanger: boolean
}

export type PropfirmAccountMetricsResult = {
  startingBalance: number
  dailyMetrics: DailyMetricsResult
  trailingMetrics: TrailingDrawdownResult
  consistencyMetrics: ConsistencyRuleResult
  totalPnL: number
  progress: PropfirmProgressResult
}

const EMPTY_TRAILING_DRAWDOWN: TrailingDrawdownResult = {
  currentBalance: 0,
  peakBalance: 0,
  drawdownFloor: 0,
  distanceToDD: 0,
  maxDrawdownUsed: 0,
  breachedTrailingDD: false,
}

const INACTIVE_CONSISTENCY_RULE: ConsistencyRuleResult = {
  biggestWin: 0,
  totalProfit: 0,
  allowedMax: 0,
  isConsistent: true,
  ruleActive: false,
}

function addCalendarDay(dateKey: string): string | null {
  const [year, month, day] = dateKey.split("-").map(Number)
  if (![year, month, day].every(Number.isFinite)) return null
  const d = new Date(Date.UTC(year, month - 1, day + 1))
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(
    2,
    "0"
  )}-${String(d.getUTCDate()).padStart(2, "0")}`
}

function resolvePropfirmTradingTimeSource(trade: {
  date?: string | null
  trade_date?: string | null
  entry_time?: string | null
}): string | null {
  const tradeDate = String(trade.trade_date ?? trade.date ?? "")
    .trim()
    .slice(0, 10)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(tradeDate)) return null

  const entryTime = String(trade.entry_time ?? "").trim()
  if (!entryTime) return tradeDate

  const parsedEntry = new Date(entryTime)
  if (!Number.isNaN(parsedEntry.getTime())) return entryTime

  const timeOnly = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(entryTime)
  if (!timeOnly) return tradeDate

  const hour = Number(timeOnly[1])
  if (!Number.isFinite(hour)) return tradeDate

  return hour >= 18 ? addCalendarDay(tradeDate) : tradeDate
}

/** Futures-style session day key using trade_date/entry_time, never import created_at. */
export function getPropfirmTradingDay(trade: {
  date?: string | null
  trade_date?: string | null
  entry_time?: string | null
}): string | null {
  const source = resolvePropfirmTradingTimeSource(trade)
  if (!source) return null
  return getTradingDayKey(source)
}

/** Parse `accounts.account_size` (number or strings like "50K", "50,000") to dollars. */
export function parseAccountSizeToNumber(account: {
  account_size?: unknown
}): number {
  const raw = account?.account_size
  if (raw == null || raw === "") return 0
  if (typeof raw === "number" && Number.isFinite(raw)) return raw
  const s = String(raw).trim().replace(/,/g, "")
  const k = /^([\d.]+)\s*k$/i.exec(s)
  if (k) {
    const n = Number(k[1])
    return Number.isFinite(n) ? n * 1000 : 0
  }
  const n = Number(s)
  return Number.isFinite(n) ? n : 0
}

export function formatPropfirmUsd(n: number): string {
  const sign = n < 0 ? "-" : ""
  return `${sign}$${Math.abs(n).toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  })}`
}

/** Drop duplicate trade rows (same `id`) so PnL is not double-counted. */
export function dedupeTradesById<T extends PropfirmTrade>(trades: T[]): T[] {
  const seen = new Set<string>()
  const out: T[] = []
  for (const t of trades) {
    const id = t?.id
    if (id != null && id !== "") {
      const key = String(id)
      if (seen.has(key)) continue
      seen.add(key)
    }
    out.push(t)
  }
  return out
}

/** Display / daily aggregation order (trade_date, then entry_time). */
export function sortTradesByTradeSequence<T extends PropfirmTrade>(trades: T[]): T[] {
  return [...trades].sort((a, b) => {
    const da = String(a.trade_date ?? a.date ?? "")
    const db = String(b.trade_date ?? b.date ?? "")
    const byDate = da.localeCompare(db)
    if (byDate !== 0) return byDate
    const at = a.entry_time ? new Date(a.entry_time).getTime() : 0
    const bt = b.entry_time ? new Date(b.entry_time).getTime() : 0
    return at - bt
  })
}

/** Trailing drawdown simulation order (legacy: created_at ascending). */
export function sortTradesByCreatedAt<T extends PropfirmTrade>(trades: T[]): T[] {
  return [...trades].sort(
    (a, b) => +new Date(a.created_at ?? 0) - +new Date(b.created_at ?? 0)
  )
}

/**
 * Trailing drawdown: floor rises with equity until it reaches the starting
 * balance. Once capped at the account size, it never trails higher.
 */
export function computeTrailingDrawdown(
  trades: PropfirmTrade[],
  startingBalance: number,
  maxDrawdown: number
): TrailingDrawdownResult {
  const maxDd = Number(maxDrawdown) || 0

  const uniqueTrades = dedupeTradesById(trades)
  const tradesSorted = sortTradesByCreatedAt(uniqueTrades)

  let balance = startingBalance
  let peakBalance = startingBalance
  let drawdownFloor = startingBalance - maxDd
  let maxDrawdownUsed = 0
  let breachedTrailingDD = false

  for (const trade of tradesSorted) {
    const pnl = parseFloat(String(trade.pnl ?? "")) || 0

    balance += pnl

    if (balance > peakBalance) {
      peakBalance = balance
      drawdownFloor = Math.min(startingBalance, peakBalance - maxDd)
    }

    const drawdownUsed = Math.max(0, drawdownFloor + maxDd - balance)
    if (drawdownUsed > maxDrawdownUsed) {
      maxDrawdownUsed = drawdownUsed
    }

    if (maxDd > 0 && balance < drawdownFloor) {
      breachedTrailingDD = true
    }
  }

  const distanceToDD = balance - drawdownFloor

  return {
    currentBalance: balance,
    peakBalance,
    drawdownFloor,
    distanceToDD,
    maxDrawdownUsed,
    breachedTrailingDD,
  }
}

/** `consistency_percent` from account rules (DB column `consistency`). */
export function computeConsistencyRule(
  trades: PropfirmTrade[],
  consistencyPercent: number
): ConsistencyRuleResult {
  const pct = Number(consistencyPercent)
  const ruleActive = Number.isFinite(pct) && pct > 0

  const winningTrades = trades.filter((t) => Number(t.pnl) > 0)
  const totalProfit = winningTrades.reduce(
    (sum, t) => sum + Number(t.pnl || 0),
    0
  )
  const biggestWin =
    winningTrades.length > 0
      ? Math.max(...winningTrades.map((t) => Number(t.pnl || 0)))
      : 0

  const allowedMax = ruleActive ? totalProfit * (pct / 100) : 0
  const isConsistent = !ruleActive || biggestWin <= allowedMax

  return {
    biggestWin,
    totalProfit,
    allowedMax,
    isConsistent,
    ruleActive,
  }
}

export function computeTotalPnL(trades: PropfirmTrade[]): number {
  return sortTradesByTradeSequence(trades).reduce(
    (sum, t) => sum + Number(t.pnl || 0),
    0
  )
}

export function getEstCalendarDayKey(date: Date = new Date()): string {
  const nowEST = new Date(
    date.toLocaleString("en-US", {
      timeZone: "America/New_York",
    })
  )
  return `${nowEST.getFullYear()}-${String(nowEST.getMonth() + 1).padStart(
    2,
    "0"
  )}-${String(nowEST.getDate()).padStart(2, "0")}`
}

export function buildDailyPnLMap(
  trades: PropfirmTrade[]
): Record<string, number> {
  const dailyPnLMap: Record<string, number> = {}

  sortTradesByTradeSequence(trades).forEach((t) => {
    const day = getPropfirmTradingDay(t)
    if (!day) return
    dailyPnLMap[day] = (dailyPnLMap[day] || 0) + Number(t.pnl || 0)
  })

  return dailyPnLMap
}

export function computeDailyMetrics(
  trades: PropfirmTrade[],
  now: Date = new Date()
): DailyMetricsResult {
  const dailyPnLMap = buildDailyPnLMap(trades)
  const dailyRows = Object.entries(dailyPnLMap).sort(([a], [b]) =>
    a.localeCompare(b)
  )
  const winningDays = Object.values(dailyPnLMap).filter((pnl) => pnl > 0).length
  const todayKey = getEstCalendarDayKey(now)
  const todayPnL = dailyPnLMap[todayKey] || 0
  const dayPnLValues = Object.values(dailyPnLMap)
  const worstDay = dayPnLValues.length > 0 ? Math.min(...dayPnLValues) : 0
  const worstDailyLossUsed = worstDay < 0 ? Math.abs(worstDay) : 0

  return {
    dailyPnLMap,
    dailyRows,
    winningDays,
    todayPnL,
    worstDay,
    worstDailyLossUsed,
  }
}

export function computePropfirmProgress(
  totalPnL: number,
  trailingMetrics: TrailingDrawdownResult,
  account: PropfirmAccountRules | null
): PropfirmProgressResult {
  const profitTarget = Number(account?.profit_target) || 0
  const maxDdLimit = Number(account?.max_drawdown) || 0
  const drawdownUsed = trailingMetrics.maxDrawdownUsed

  const progressPercent = profitTarget
    ? Math.min((totalPnL / profitTarget) * 100, 100)
    : 0

  const isPassed = !!account && profitTarget > 0 && totalPnL >= profitTarget
  const isFailed =
    !!account &&
    maxDdLimit > 0 &&
    (trailingMetrics.breachedTrailingDD || trailingMetrics.distanceToDD < 0)

  const status: PropfirmProgressResult["status"] = isFailed
    ? "FAILED"
    : isPassed
      ? "PASSED"
      : "IN PROGRESS"

  const ddPercent =
    maxDdLimit > 0 ? Math.min((drawdownUsed / maxDdLimit) * 100, 100) : 0

  const distanceToDD = trailingMetrics.distanceToDD
  const distanceDanger =
    maxDdLimit > 0 &&
    distanceToDD >= 0 &&
    distanceToDD < 0.2 * maxDdLimit

  return {
    totalPnL,
    progressPercent,
    isPassed,
    isFailed,
    status,
    ddPercent,
    distanceDanger,
  }
}

export function computePropfirmAccountMetrics(
  trades: PropfirmTrade[],
  account: PropfirmAccountRules | null
): PropfirmAccountMetricsResult {
  const dailyMetrics = computeDailyMetrics(trades)
  const totalPnL = computeTotalPnL(trades)
  const startingBalance = account ? parseAccountSizeToNumber(account) : 0
  const trailingMetrics = account
    ? computeTrailingDrawdown(
        trades,
        startingBalance,
        Number(account.max_drawdown) || 0
      )
    : EMPTY_TRAILING_DRAWDOWN
  const consistencyMetrics = account
    ? computeConsistencyRule(trades, Number(account.consistency) || 0)
    : INACTIVE_CONSISTENCY_RULE
  const progress = computePropfirmProgress(totalPnL, trailingMetrics, account)

  return {
    startingBalance,
    dailyMetrics,
    trailingMetrics,
    consistencyMetrics,
    totalPnL,
    progress,
  }
}
