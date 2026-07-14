import { normalizeSessionBucket } from "@/lib/dashboardSessionBuckets"
import {
  getDashboardTradingDayKey,
  resolveDashboardTradeDate,
  resolveDashboardTradeTimeSource,
} from "@/lib/dashboardTradeDate"
import { resolveTradeDurationSeconds } from "@/lib/dashboardHoldTimeStats"
import { formatPnlCurrency } from "@/lib/formatMoney"
import { formatRR } from "@/lib/formatDisplay"
import { averageRrFromTrades } from "@/lib/tradeRr"
import { computePerformanceStats } from "@/lib/performanceShare"
import {
  formatTradingReportDateRange,
  getTradingReportPeriodBounds,
  tradingReportPeriodTitle,
  type TradingReportPeriodBounds,
} from "./tradingReportPeriods"
import type {
  TradingReport,
  TradingReportMetrics,
  TradingReportPeriodKey,
} from "./tradingReportTypes"

const WEEKDAY_LABELS = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
] as const

const SESSION_LABELS: Record<string, string> = {
  NY: "New York",
  London: "London",
  Asia: "Asia",
}

function filterTradesForBounds(trades: any[], bounds: TradingReportPeriodBounds): any[] {
  return trades.filter((trade) => {
    const tradeDate = resolveDashboardTradeDate(trade)
    if (!tradeDate) return false
    return tradeDate >= bounds.start && tradeDate <= bounds.end
  })
}

function parseHourFromTimeSource(timeSource: unknown): number | null {
  if (timeSource == null || timeSource === "") return null
  const raw = String(timeSource).trim()
  if (!raw) return null

  const date = new Date(raw)
  if (!Number.isNaN(date.getTime())) return date.getHours()

  const match = raw.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/)
  if (!match) return null
  const hour = parseInt(match[1], 10)
  if (!Number.isFinite(hour) || hour < 0 || hour > 23) return null
  return hour
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
    const key = getDashboardTradingDayKey(trade)
    if (!key) continue
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

function computeSessionPnl(trades: any[]): Map<string, number> {
  const map = new Map<string, number>()
  for (const trade of trades) {
    const bucket = normalizeSessionBucket(trade.session)
    if (!bucket) continue
    map.set(bucket, (map.get(bucket) ?? 0) + (Number(trade.pnl) || 0))
  }
  return map
}

function pickExtremeSession(
  sessions: Map<string, number>,
  mode: "best" | "worst"
): { label: string | null; pnl: number | null } {
  if (sessions.size === 0) return { label: null, pnl: null }

  let pickedKey: string | null = null
  let pickedPnl = mode === "best" ? -Infinity : Infinity

  for (const [key, pnl] of sessions) {
    if (mode === "best" ? pnl > pickedPnl : pnl < pickedPnl) {
      pickedKey = key
      pickedPnl = pnl
    }
  }

  if (!pickedKey) return { label: null, pnl: null }
  return {
    label: SESSION_LABELS[pickedKey] ?? pickedKey,
    pnl: pickedPnl,
  }
}

function computeWeekdayPnl(trades: any[]): Map<number, number> {
  const map = new Map<number, number>()
  for (const trade of trades) {
    const date = resolveDashboardTradeDate(trade)
    if (!date) continue
    const day = date.getDay()
    map.set(day, (map.get(day) ?? 0) + (Number(trade.pnl) || 0))
  }
  return map
}

function computeHourlyPnl(trades: any[]): Map<number, number> {
  const map = new Map<number, number>()
  for (const trade of trades) {
    const source = resolveDashboardTradeTimeSource(trade)
    const hour = parseHourFromTimeSource(source)
    if (hour == null) continue
    map.set(hour, (map.get(hour) ?? 0) + (Number(trade.pnl) || 0))
  }
  return map
}

function computeStrategyPnl(trades: any[]): Map<string, number> {
  const map = new Map<string, number>()
  for (const trade of trades) {
    const raw = trade.strategy != null ? String(trade.strategy).trim() : ""
    if (!raw) continue
    map.set(raw, (map.get(raw) ?? 0) + (Number(trade.pnl) || 0))
  }
  return map
}

function detectLossesAfterWinStreak(trades: any[]): number {
  const sorted = [...trades].sort((a, b) => {
    const ta = resolveDashboardTradeDate(a)?.getTime() ?? 0
    const tb = resolveDashboardTradeDate(b)?.getTime() ?? 0
    return ta - tb
  })

  let winStreak = 0
  let lossAfterStreak = 0

  for (const trade of sorted) {
    const pnl = Number(trade.pnl) || 0
    if (pnl > 0) {
      winStreak += 1
      continue
    }
    if (pnl < 0 && winStreak >= 2) {
      lossAfterStreak += 1
    }
    winStreak = 0
  }

  return lossAfterStreak
}

function formatHourLabel(hour: number): string {
  const period = hour >= 12 ? "PM" : "AM"
  const h = hour % 12 === 0 ? 12 : hour % 12
  return `${h}:00 ${period}`
}

function buildMetrics(trades: any[]): TradingReportMetrics {
  const stats = computePerformanceStats(trades)
  const daily = computeDailyPnl(trades)
  const sessions = computeSessionPnl(trades)
  const bestDay = pickExtremeDay(daily, "best")
  const worstDay = pickExtremeDay(daily, "worst")
  const bestSession = pickExtremeSession(sessions, "best")
  const worstSession = pickExtremeSession(sessions, "worst")

  return {
    netPnl: stats.totalPnL,
    winRate: stats.winRate,
    averageRr: stats.avgRR,
    profitFactor: computeProfitFactor(trades),
    tradesTaken: stats.totalTrades,
    bestDayLabel: bestDay.label,
    bestDayPnl: bestDay.pnl,
    worstDayLabel: worstDay.label,
    worstDayPnl: worstDay.pnl,
    bestSessionLabel: bestSession.label,
    bestSessionPnl: bestSession.pnl,
    worstSessionLabel: worstSession.label,
    worstSessionPnl: worstSession.pnl,
    mostTradedSymbol: stats.mostTradedTicker,
    averageHoldTimeSeconds: stats.avgDurationSeconds,
  }
}

function buildExecutiveSummary(
  metrics: TradingReportMetrics,
  kind: TradingReport["kind"]
): string {
  const periodLabel = kind === "weekly" ? "week" : "month"

  if (metrics.tradesTaken === 0) {
    return `No trades were logged during this ${periodLabel}. Log your next session to unlock personalized insights here.`
  }

  const tone =
    metrics.netPnl > 0
      ? "positive"
      : metrics.netPnl < 0
        ? "challenging"
        : "mixed"

  const execution =
    metrics.winRate >= 55
      ? "solid win rate"
      : metrics.winRate <= 40
        ? "a win rate that needs attention"
        : "a balanced win rate"

  const risk =
    metrics.profitFactor != null && metrics.profitFactor >= 1.5
      ? "healthy profit factor"
      : metrics.profitFactor != null && metrics.profitFactor < 1
        ? "profit factor below breakeven"
        : "moderate profit factor"

  const rr =
    metrics.averageRr != null && metrics.averageRr >= 1.5
      ? "strong average Risk:Reward"
      : metrics.averageRr != null && metrics.averageRr < 1
        ? "below-target Risk:Reward"
        : "steady Risk:Reward"

  return `Overall, you had a ${tone} ${periodLabel} with ${metrics.tradesTaken} trade${
    metrics.tradesTaken === 1 ? "" : "s"
  } and ${formatPnlCurrency(metrics.netPnl)} net P&L. You posted ${execution} with ${risk} and ${rr}.`
}

function buildStrengths(
  trades: any[],
  metrics: TradingReportMetrics,
  comparisonTrades: any[] | null
): string[] {
  const strengths: string[] = []

  if (
    metrics.bestSessionLabel &&
    metrics.bestSessionPnl != null &&
    metrics.bestSessionPnl > 0
  ) {
    strengths.push(
      `You performed best during the ${metrics.bestSessionLabel} session (${formatPnlCurrency(metrics.bestSessionPnl)}).`
    )
  }

  if (metrics.winRate >= 55 && metrics.tradesTaken >= 3) {
    strengths.push(
      `Your win rate was ${metrics.winRate.toFixed(1)}% across ${metrics.tradesTaken} trades.`
    )
  }

  if (metrics.profitFactor != null && metrics.profitFactor >= 1.5) {
    strengths.push(
      `Profit factor reached ${metrics.profitFactor.toFixed(2)}, showing winners outweighed losers.`
    )
  }

  if (metrics.averageRr != null && metrics.averageRr >= 1.2) {
    strengths.push(`Average Risk:Reward was ${formatRR(metrics.averageRr)}.`)
  }

  if (comparisonTrades && comparisonTrades.length >= 3) {
    const priorRr = averageRrFromTrades(comparisonTrades)
    if (
      metrics.averageRr != null &&
      priorRr != null &&
      metrics.averageRr > priorRr * 1.05
    ) {
      const pct = Math.round(((metrics.averageRr - priorRr) / priorRr) * 100)
      strengths.push(`Your average RR improved by ${pct}% versus the prior period.`)
    }
  }

  const strategies = computeStrategyPnl(trades)
  let bestStrategy: string | null = null
  let bestStrategyPnl = -Infinity
  for (const [name, pnl] of strategies) {
    if (pnl > bestStrategyPnl) {
      bestStrategy = name
      bestStrategyPnl = pnl
    }
  }
  if (bestStrategy && bestStrategyPnl > 0) {
    strengths.push(
      `Your top setup was ${bestStrategy} (${formatPnlCurrency(bestStrategyPnl)}).`
    )
  }

  if (metrics.netPnl > 0 && metrics.tradesTaken >= 3) {
    strengths.push("You finished the period net positive.")
  }

  return strengths.slice(0, 5)
}

function buildOpportunities(trades: any[], metrics: TradingReportMetrics): string[] {
  const opportunities: string[] = []

  if (
    metrics.worstSessionLabel &&
    metrics.worstSessionPnl != null &&
    metrics.worstSessionPnl < 0
  ) {
    opportunities.push(
      `${metrics.worstSessionLabel} session trades lost ${formatPnlCurrency(
        Math.abs(metrics.worstSessionPnl)
      )}.`
    )
  }

  const hourly = computeHourlyPnl(trades)
  if (hourly.size >= 2) {
    let afternoonPnl = 0
    let morningPnl = 0
    for (const [hour, pnl] of hourly) {
      if (hour >= 12) afternoonPnl += pnl
      else morningPnl += pnl
    }
    if (afternoonPnl < morningPnl && afternoonPnl < 0) {
      opportunities.push("Afternoon trades underperformed relative to the morning.")
    }
  }

  const lossesAfterWins = detectLossesAfterWinStreak(trades)
  if (lossesAfterWins >= 2) {
    opportunities.push(
      `${lossesAfterWins} losing trades followed consecutive winners. Watch for overconfidence.`
    )
  }

  const weekdays = computeWeekdayPnl(trades)
  if (weekdays.size >= 2) {
    let worstDay = -1
    let worstPnl = Infinity
    for (const [day, pnl] of weekdays) {
      if (pnl < worstPnl) {
        worstDay = day
        worstPnl = pnl
      }
    }
    if (worstDay >= 0 && worstPnl < 0) {
      opportunities.push(
        `${WEEKDAY_LABELS[worstDay]} was your weakest weekday (${formatPnlCurrency(
          worstPnl
        )}).`
      )
    }
  }

  if (metrics.averageRr != null && metrics.averageRr < 1 && metrics.tradesTaken >= 3) {
    opportunities.push(
      `Average Risk:Reward was ${formatRR(metrics.averageRr)}. Review exits and stop placement.`
    )
  }

  if (metrics.profitFactor != null && metrics.profitFactor < 1 && metrics.tradesTaken >= 3) {
    opportunities.push(
      `Profit factor was ${metrics.profitFactor.toFixed(2)}. Losses exceeded gains.`
    )
  }

  const hourlyWorst = [...hourly.entries()].sort((a, b) => a[1] - b[1])[0]
  if (hourlyWorst && hourlyWorst[1] < 0 && hourly.size >= 3) {
    opportunities.push(
      `Trades around ${formatHourLabel(hourlyWorst[0])} were your weakest hour block.`
    )
  }

  return opportunities.slice(0, 5)
}

function buildRecommendations(
  strengths: string[],
  opportunities: string[],
  metrics: TradingReportMetrics
): string[] {
  const recommendations: string[] = []

  const bestSetup = strengths.find((s) => s.includes("top setup"))
  if (bestSetup) {
    recommendations.push("Continue focusing on your best-performing setup.")
  }

  if (opportunities.some((o) => o.toLowerCase().includes("afternoon"))) {
    recommendations.push("Reduce afternoon trading exposure until performance improves.")
  }

  if (opportunities.some((o) => o.includes("consecutive winners"))) {
    recommendations.push("Review losing trades taken after extended win streaks.")
  }

  if (metrics.profitFactor != null && metrics.profitFactor >= 1.2) {
    recommendations.push("Maintain your current risk management discipline.")
  } else if (metrics.tradesTaken >= 3) {
    recommendations.push("Tighten risk per trade until profit factor recovers above 1.0.")
  }

  if (
    metrics.bestSessionLabel &&
    metrics.bestSessionPnl != null &&
    metrics.bestSessionPnl > 0
  ) {
    recommendations.push(`Prioritize ${metrics.bestSessionLabel} session setups that are working.`)
  }

  recommendations.push("Keep journaling consistently to sharpen future reports.")

  const unique = [...new Set(recommendations)]
  return unique.slice(0, 5)
}

function buildKeyTakeaway(
  metrics: TradingReportMetrics,
  strengths: string[],
  opportunities: string[]
): string {
  if (metrics.tradesTaken === 0) {
    return "Consistent journaling unlocks sharper weekly and monthly intelligence. Log your next trade to start building your report history."
  }

  if (strengths.length > 0 && opportunities.length > 0) {
    return `${strengths[0].replace(/\.$/, "")}, but ${opportunities[0].charAt(0).toLowerCase()}${opportunities[0].slice(1)}`
  }

  if (metrics.netPnl > 0) {
    return `Your edge showed up in the data this period. Protect it by doubling down on what worked and trimming the sessions that dragged performance.`
  }

  if (metrics.netPnl < 0) {
    return `This period highlights where leakage occurred. Use the session and timing breakdowns above to tighten execution next week.`
  }

  return `Stay process-focused: the metrics above show where your execution helped and where small adjustments can compound over the next reporting period.`
}

function findBestTrade(trades: any[]): any | null {
  if (trades.length === 0) return null
  return [...trades].sort(
    (a, b) => (Number(b.pnl) || 0) - (Number(a.pnl) || 0)
  )[0]
}

function comparisonPeriodKey(
  key: TradingReportPeriodKey
): TradingReportPeriodKey | null {
  switch (key) {
    case "weekly_this":
      return "weekly_last"
    case "monthly_this":
      return "monthly_last"
    default:
      return null
  }
}

export function generateTradingReport(
  trades: any[],
  periodKey: TradingReportPeriodKey,
  now = new Date()
): TradingReport {
  const bounds = getTradingReportPeriodBounds(periodKey, now)
  const periodTrades = filterTradesForBounds(trades, bounds)
  const metrics = buildMetrics(periodTrades)

  const comparisonKey = comparisonPeriodKey(periodKey)
  const comparisonTrades = comparisonKey
    ? filterTradesForBounds(trades, getTradingReportPeriodBounds(comparisonKey, now))
    : null

  const strengths = buildStrengths(periodTrades, metrics, comparisonTrades)
  const opportunities = buildOpportunities(periodTrades, metrics)
  const recommendations = buildRecommendations(strengths, opportunities, metrics)
  const bestTrade = findBestTrade(periodTrades)

  return {
    periodKey,
    kind: bounds.kind,
    title: tradingReportPeriodTitle(bounds.kind),
    dateRangeLabel: formatTradingReportDateRange(
      bounds.start,
      bounds.end,
      bounds.kind
    ),
    periodStartIso: bounds.start.toISOString(),
    periodEndIso: bounds.end.toISOString(),
    generatedAt: Date.now(),
    executiveSummary: buildExecutiveSummary(metrics, bounds.kind),
    metrics,
    strengths,
    opportunities,
    recommendations,
    bestTradeId: bestTrade?.id != null ? String(bestTrade.id) : null,
    keyTakeaway: buildKeyTakeaway(metrics, strengths, opportunities),
    summarySource: "deterministic",
  }
}

export function generateAllTradingReports(
  trades: any[],
  now = new Date()
): Record<TradingReportPeriodKey, TradingReport> {
  return {
    weekly_this: generateTradingReport(trades, "weekly_this", now),
    weekly_last: generateTradingReport(trades, "weekly_last", now),
    monthly_this: generateTradingReport(trades, "monthly_this", now),
    monthly_last: generateTradingReport(trades, "monthly_last", now),
  }
}
