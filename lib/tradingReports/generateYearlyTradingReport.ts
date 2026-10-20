import type { EquityChartPoint } from "@/app/components/dashboard/DashboardEquityCurve"
import {
  compareDashboardTradesChronological,
  resolveDashboardTradeDate,
} from "@/lib/dashboardTradeDate"
import { computeMaxDrawdown } from "@/lib/dashboardMaxDrawdown"
import { formatPnlCurrency } from "@/lib/formatMoney"
import { computePerformanceStats } from "@/lib/performanceShare"
import { generateTradingReportForTrades } from "./generateTradingReport"
import {
  availableTradingReportYears,
  formatTradingYearDateRangeLabel,
  getTradingMonthBounds,
  getTradingYearBounds,
  isBacktestTrade,
  monthLabel,
  shortMonthLabel,
} from "./tradingYearlyReportPeriods"
import type {
  TradingReportMonthRef,
  TradingYearlyMonthMetrics,
  TradingYearlyMonthRow,
  TradingYearlyReport,
  TradingYearlyReportMetrics,
} from "./tradingYearlyReportTypes"
import type { TradingReport } from "./tradingReportTypes"

export { availableTradingReportYears }

function filterTradesForInterval(trades: any[], start: Date, end: Date): any[] {
  return trades.filter((trade) => {
    if (isBacktestTrade(trade)) return false
    const tradeDate = resolveDashboardTradeDate(trade)
    if (!tradeDate) return false
    return tradeDate >= start && tradeDate <= end
  })
}

function computeProfitFactor(trades: any[]): number | null {
  const grossProfit = trades
    .filter((t) => (Number(t.pnl) || 0) > 0)
    .reduce((sum, t) => sum + (Number(t.pnl) || 0), 0)
  const grossLoss = trades
    .filter((t) => (Number(t.pnl) || 0) < 0)
    .reduce((sum, t) => sum + Math.abs(Number(t.pnl) || 0), 0)
  if (grossLoss === 0) return grossProfit > 0 ? null : null
  return grossProfit / grossLoss
}

function computeDailyPnl(trades: any[]): Map<string, number> {
  const map = new Map<string, number>()
  for (const trade of trades) {
    const date = resolveDashboardTradeDate(trade)
    if (!date) continue
    const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`
    map.set(key, (map.get(key) ?? 0) + (Number(trade.pnl) || 0))
  }
  return map
}

function pickExtremeDay(
  daily: Map<string, number>,
  mode: "best" | "worst"
): { label: string | null; pnl: number | null } {
  if (daily.size === 0) return { label: null, pnl: null }
  let pickedKey: string | null = null
  let pickedPnl = mode === "best" ? -Infinity : Infinity
  for (const [key, pnl] of daily) {
    if (mode === "best" ? pnl > pickedPnl : pnl < pickedPnl) {
      pickedKey = key
      pickedPnl = pnl
    }
  }
  if (!pickedKey) return { label: null, pnl: null }
  const date = new Date(`${pickedKey}T12:00:00`)
  if (Number.isNaN(date.getTime())) {
    return { label: pickedKey, pnl: pickedPnl }
  }
  return {
    label: date.toLocaleDateString(undefined, {
      weekday: "short",
      month: "short",
      day: "numeric",
    }),
    pnl: pickedPnl,
  }
}

function averagePnl(trades: any[], wins: boolean): number | null {
  const filtered = trades.filter((t) =>
    wins ? (Number(t.pnl) || 0) > 0 : (Number(t.pnl) || 0) < 0
  )
  if (filtered.length === 0) return null
  const sum = filtered.reduce((s, t) => s + (Number(t.pnl) || 0), 0)
  return sum / filtered.length
}

function computeExpectancy(trades: any[]): number | null {
  if (trades.length === 0) return null
  const wins = trades.filter((t) => (Number(t.pnl) || 0) > 0)
  const losses = trades.filter((t) => (Number(t.pnl) || 0) < 0)
  const winRate = wins.length / trades.length
  const lossRate = losses.length / trades.length
  const avgWin = averagePnl(trades, true) ?? 0
  const avgLoss = averagePnl(trades, false) ?? 0
  return winRate * avgWin + lossRate * avgLoss
}

function buildYearlyMetrics(trades: any[]): TradingYearlyReportMetrics {
  const stats = computePerformanceStats(trades)
  const daily = computeDailyPnl(trades)
  const bestDay = pickExtremeDay(daily, "best")
  const worstDay = pickExtremeDay(daily, "worst")
  const wins = trades.filter((t) => (Number(t.pnl) || 0) > 0)
  const losses = trades.filter((t) => (Number(t.pnl) || 0) < 0)
  let bestTrade: number | null = null
  let worstTrade: number | null = null
  for (const t of trades) {
    const pnl = Number(t.pnl) || 0
    if (bestTrade == null || pnl > bestTrade) bestTrade = pnl
    if (worstTrade == null || pnl < worstTrade) worstTrade = pnl
  }
  const winningDays = [...daily.values()].filter((v) => v > 0).length
  const losingDays = [...daily.values()].filter((v) => v < 0).length

  return {
    netPnl: stats.totalPnL,
    tradeCount: stats.totalTrades,
    winRate: stats.totalTrades > 0 ? stats.winRate : null,
    profitFactor: computeProfitFactor(trades),
    averageWinner: averagePnl(trades, true),
    averageLoser: averagePnl(trades, false),
    averageRr: stats.avgRR,
    expectancy: computeExpectancy(trades),
    bestTrade: trades.length > 0 ? bestTrade : null,
    worstTrade: trades.length > 0 ? worstTrade : null,
    bestDayLabel: bestDay.label,
    bestDayPnl: bestDay.pnl,
    worstDayLabel: worstDay.label,
    worstDayPnl: worstDay.pnl,
    maxDrawdown: computeMaxDrawdown(trades),
    winningDays,
    losingDays,
    winCount: wins.length,
    lossCount: losses.length,
  }
}

function buildEquityCurve(trades: any[]): EquityChartPoint[] {
  const chronological = [...trades].sort(compareDashboardTradesChronological)
  let running = 0
  return chronological.map((trade) => {
    running += Number(trade.pnl) || 0
    const date = resolveDashboardTradeDate(trade)
    return {
      date: (date ?? new Date()).toISOString(),
      equity: running,
    }
  })
}

function buildExecutiveSummary(
  metrics: TradingYearlyReportMetrics,
  year: number
): string {
  if (metrics.tradeCount === 0) {
    return `No trades matched your filters during ${year}. Log trades to unlock yearly insights.`
  }
  const tone =
    metrics.netPnl > 0 ? "positive" : metrics.netPnl < 0 ? "challenging" : "mixed"
  const winRateText =
    metrics.winRate != null
      ? `${metrics.winRate.toFixed(1)}% win rate`
      : "no closed trades"
  return `${year} was a ${tone} year with ${metrics.tradeCount} trades and ${formatPnlCurrency(metrics.netPnl)} net P&L. You finished with ${winRateText} across ${metrics.winningDays} winning days and ${metrics.losingDays} losing days.`
}

function buildMonthRows(
  year: number,
  trades: any[],
  now: Date
): TradingYearlyMonthRow[] {
  const currentYear = now.getFullYear()
  const currentMonth = now.getMonth() + 1
  const rows: TradingYearlyMonthRow[] = []

  for (let month = 1; month <= 12; month += 1) {
    const label = monthLabel(month)
    if (year > currentYear || (year === currentYear && month > currentMonth)) {
      rows.push({ month, monthLabel: label, availability: { kind: "upcoming" } })
      continue
    }
    const bounds = getTradingMonthBounds(year, month, now)
    const monthTrades = filterTradesForInterval(trades, bounds.start, bounds.end)
    const stats = computePerformanceStats(monthTrades)
    const monthRef: TradingReportMonthRef = { year, month }
    const metrics: TradingYearlyMonthMetrics = {
      year,
      month,
      monthLabel: label,
      netPnl: stats.totalPnL,
      tradeCount: stats.totalTrades,
      winRate: stats.totalTrades > 0 ? stats.winRate : null,
      monthRef,
    }
    rows.push({
      month,
      monthLabel: label,
      availability: { kind: "available", metrics },
    })
  }
  return rows
}

export function generateYearlyTradingReport(
  trades: any[],
  year: number,
  now = new Date()
): TradingYearlyReport {
  const bounds = getTradingYearBounds(year, now)
  const scopedTrades = filterTradesForInterval(trades, bounds.start, bounds.end)
  const metrics = buildYearlyMetrics(scopedTrades)
  const monthRows = buildMonthRows(year, trades, now)
  const availableMonths = monthRows
    .map((row) =>
      row.availability.kind === "available" ? row.availability.metrics : null
    )
    .filter((m): m is TradingYearlyMonthMetrics => m != null && m.tradeCount > 0)
  const strongestMonth =
    availableMonths.length > 0
      ? availableMonths.reduce((a, b) => (a.netPnl >= b.netPnl ? a : b))
      : null
  const weakestMonth =
    availableMonths.length > 0
      ? availableMonths.reduce((a, b) => (a.netPnl <= b.netPnl ? a : b))
      : null
  const monthlyPnLBars = monthRows
    .map((row) => {
      if (row.availability.kind !== "available") return null
      return {
        label: shortMonthLabel(row.month),
        value: row.availability.metrics.netPnl,
      }
    })
    .filter((b): b is { label: string; value: number } => b != null)

  return {
    year,
    title: `${year} Performance Report`,
    dateRangeLabel: formatTradingYearDateRangeLabel(year, now),
    periodStartIso: bounds.start.toISOString(),
    periodEndIso: bounds.end.toISOString(),
    generatedAt: Date.now(),
    executiveSummary: buildExecutiveSummary(metrics, year),
    metrics,
    monthRows,
    monthlyPnLBars,
    strongestMonth,
    weakestMonth,
    equityCurve: buildEquityCurve(scopedTrades),
  }
}

export function generateYearMonthTradingReport(
  ref: TradingReportMonthRef,
  trades: any[],
  now = new Date()
): TradingReport {
  const bounds = getTradingMonthBounds(ref.year, ref.month, now)
  const monthTrades = filterTradesForInterval(trades, bounds.start, bounds.end)
  const label = monthLabel(ref.month)
  const report = generateTradingReportForTrades(monthTrades, {
    title: `${label} ${ref.year} Report`,
    dateRangeLabel: `${label} ${ref.year}`,
    kind: "monthly",
  })
  if (report.metrics.tradesTaken === 0) {
    return {
      ...report,
      executiveSummary: `No trades matched your filters during ${label} ${ref.year}.`,
      keyTakeaway: "This month had no matching trades for your active filters.",
      strengths: [],
      opportunities: [],
      recommendations: [],
    }
  }
  const m = report.metrics
  return {
    ...report,
    executiveSummary: `${label} ${ref.year}: ${m.tradesTaken} trades and ${formatPnlCurrency(m.netPnl)} net P&L with ${m.winRate.toFixed(1)}% win rate.`,
    keyTakeaway:
      m.netPnl > 0
        ? "Net positive month — review what worked and carry those habits forward."
        : m.netPnl < 0
          ? "Review session timing and risk per trade to tighten execution next month."
          : "Stay process-focused — small adjustments compound across the year.",
    strengths: [],
    opportunities: [],
    recommendations: [],
  }
}
