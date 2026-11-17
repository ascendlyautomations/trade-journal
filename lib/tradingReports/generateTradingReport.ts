import {
  COMPARATIVE_MIN_PER_SIDE,
  easternHour,
  knownPnl,
} from "@/lib/analytics/knownPnl"
import {
  complianceTradeFromRow,
  evaluatePreferenceCompliance,
  primaryRuleAdjustment,
  type PreferenceRuleContext,
} from "@/lib/analytics/preferenceCompliance"
import { normalizeSessionBucket } from "@/lib/dashboardSessionBuckets"
import { tradingSessionDisplayName } from "@/lib/tradingSession"
import { resolveDashboardTradeTimeSource } from "@/lib/dashboardTradeDate"
import { resolveTradeDurationSeconds } from "@/lib/dashboardHoldTimeStats"
import { formatPnlCurrency } from "@/lib/formatMoney"
import { formatRR } from "@/lib/formatDisplay"
import { averageRrFromTrades } from "@/lib/tradeRr"
import { psychologyTradeDateKey } from "@/lib/psychology/tradeDateKey"
import {
  absoluteTradingWeekBounds,
  comparablePriorReportBounds,
  formatTradingReportDateRange,
  getTradingReportPeriodBounds,
  parseTradingReportWeekPeriodId,
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

function filterTradesForBounds(trades: any[], bounds: TradingReportPeriodBounds): any[] {
  return trades.filter((trade) => {
    const key = psychologyTradeDateKey(trade)
    if (!key) return false
    return key >= bounds.startKey && key <= bounds.endKey
  })
}

function easternHourFromSource(timeSource: unknown): number | null {
  if (timeSource == null || timeSource === "") return null
  const raw = String(timeSource).trim()
  if (!raw) return null
  const date = new Date(raw)
  if (!Number.isNaN(date.getTime())) return easternHour(date)
  const match = raw.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/)
  if (!match) return null
  const hour = parseInt(match[1], 10)
  if (!Number.isFinite(hour) || hour < 0 || hour > 23) return null
  return hour
}

function knownResults(trades: any[]): number[] {
  return trades.flatMap((trade) => {
    const pnl = knownPnl(trade.pnl)
    return pnl == null ? [] : [pnl]
  })
}

function computeProfitFactor(trades: any[]): number | null {
  const values = knownResults(trades)
  const grossProfit = values.filter((pnl) => pnl > 0).reduce((sum, pnl) => sum + pnl, 0)
  const grossLoss = values
    .filter((pnl) => pnl < 0)
    .reduce((sum, pnl) => sum + Math.abs(pnl), 0)
  if (grossLoss === 0) return null
  return grossProfit / grossLoss
}

type PricedBucket = { pnl: number; count: number }

function addPriced(map: Map<string, PricedBucket>, key: string, pnl: number) {
  const row = map.get(key) ?? { pnl: 0, count: 0 }
  row.pnl += pnl
  row.count += 1
  map.set(key, row)
}

function computeDailyPnl(trades: any[]): Map<string, PricedBucket> {
  const map = new Map<string, PricedBucket>()
  for (const trade of trades) {
    const key = psychologyTradeDateKey(trade)
    const pnl = knownPnl(trade.pnl)
    if (!key || pnl == null) continue
    addPriced(map, key, pnl)
  }
  return map
}

function formatEasternDayLabel(key: string): string {
  const date = new Date(`${key}T16:00:00Z`)
  if (Number.isNaN(date.getTime())) return key
  return date.toLocaleDateString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
    timeZone: "America/New_York",
  })
}

function pickExtremeDay(
  daily: Map<string, PricedBucket>,
  mode: "best" | "worst"
): { label: string | null; pnl: number | null } {
  if (daily.size < 2) return { label: null, pnl: null }
  const eligible = [...daily.entries()].filter(([, row]) =>
    mode === "best" ? row.pnl > 0 : row.pnl < 0
  )
  if (eligible.length === 0) return { label: null, pnl: null }
  eligible.sort((a, b) =>
    mode === "best" ? b[1].pnl - a[1].pnl : a[1].pnl - b[1].pnl
  )
  const [key, row] = eligible[0]
  const opposite = [...daily.values()].some((other) =>
    mode === "best" ? other.pnl < row.pnl : other.pnl > row.pnl
  )
  if (!opposite) return { label: null, pnl: null }
  return { label: formatEasternDayLabel(key), pnl: row.pnl }
}

function computeSessionPnl(trades: any[]): Map<string, PricedBucket> {
  const map = new Map<string, PricedBucket>()
  for (const trade of trades) {
    const bucket = normalizeSessionBucket(trade.session)
    const pnl = knownPnl(trade.pnl)
    if (!bucket || pnl == null) continue
    addPriced(map, bucket, pnl)
  }
  return map
}

function pickExtremeSession(
  sessions: Map<string, PricedBucket>,
  mode: "best" | "worst"
): { label: string | null; pnl: number | null } {
  const rows = [...sessions.entries()].filter(
    ([, row]) => row.count >= COMPARATIVE_MIN_PER_SIDE
  )
  if (rows.length < 2) return { label: null, pnl: null }
  rows.sort((a, b) => (mode === "best" ? b[1].pnl - a[1].pnl : a[1].pnl - b[1].pnl))
  const [key, row] = rows[0]
  if (mode === "best" && row.pnl <= 0) return { label: null, pnl: null }
  if (mode === "worst" && row.pnl >= 0) return { label: null, pnl: null }
  return { label: tradingSessionDisplayName(key), pnl: row.pnl }
}

function easternWeekdayIndex(key: string): number | null {
  const date = new Date(`${key}T16:00:00Z`)
  if (Number.isNaN(date.getTime())) return null
  const name = date.toLocaleDateString("en-US", {
    weekday: "long",
    timeZone: "America/New_York",
  })
  const index = WEEKDAY_LABELS.indexOf(name as (typeof WEEKDAY_LABELS)[number])
  return index >= 0 ? index : null
}

function computeWeekdayPnl(trades: any[]): Map<number, PricedBucket> {
  const map = new Map<number, PricedBucket>()
  for (const trade of trades) {
    const key = psychologyTradeDateKey(trade)
    const pnl = knownPnl(trade.pnl)
    if (!key || pnl == null) continue
    const day = easternWeekdayIndex(key)
    if (day == null) continue
    const row = map.get(day) ?? { pnl: 0, count: 0 }
    row.pnl += pnl
    row.count += 1
    map.set(day, row)
  }
  return map
}

function computeHourlyPnl(trades: any[]): Map<number, PricedBucket> {
  const map = new Map<number, PricedBucket>()
  for (const trade of trades) {
    const source = resolveDashboardTradeTimeSource(trade)
    const hour = easternHourFromSource(source)
    const pnl = knownPnl(trade.pnl)
    if (hour == null || pnl == null) continue
    const row = map.get(hour) ?? { pnl: 0, count: 0 }
    row.pnl += pnl
    row.count += 1
    map.set(hour, row)
  }
  return map
}

function computeStrategyPnl(trades: any[]): Map<string, PricedBucket> {
  const map = new Map<string, PricedBucket>()
  for (const trade of trades) {
    const raw = trade.strategy != null ? String(trade.strategy).trim() : ""
    const pnl = knownPnl(trade.pnl)
    if (!raw || pnl == null) continue
    addPriced(map, raw, pnl)
  }
  return map
}

function formatHourLabel(hour: number): string {
  const period = hour >= 12 ? "PM" : "AM"
  const h = hour % 12 === 0 ? 12 : hour % 12
  return `${h}:00 ${period}`
}

function mostTradedSymbol(trades: any[]): string | null {
  const counts = new Map<string, number>()
  for (const trade of trades) {
    const raw = trade.ticker != null ? String(trade.ticker).trim().toUpperCase() : ""
    if (!raw) continue
    counts.set(raw, (counts.get(raw) ?? 0) + 1)
  }
  let best: string | null = null
  let bestCount = 0
  for (const [ticker, count] of counts) {
    if (count > bestCount) {
      best = ticker
      bestCount = count
    }
  }
  return best
}

function averageHoldSeconds(trades: any[]): number | null {
  const durations = trades
    .map(resolveTradeDurationSeconds)
    .filter((seconds): seconds is number => seconds != null)
  if (durations.length === 0) return null
  return Math.round(durations.reduce((sum, seconds) => sum + seconds, 0) / durations.length)
}

function buildMetrics(trades: any[]): TradingReportMetrics {
  const priced = knownResults(trades)
  const wins = priced.filter((pnl) => pnl > 0).length
  const daily = computeDailyPnl(trades)
  const sessions = computeSessionPnl(trades)
  const bestDay = pickExtremeDay(daily, "best")
  const worstDay = pickExtremeDay(daily, "worst")
  const bestSession = pickExtremeSession(sessions, "best")
  const worstSession = pickExtremeSession(sessions, "worst")
  const sameDay =
    bestDay.label != null && bestDay.label === worstDay.label

  return {
    netPnl: priced.reduce((sum, pnl) => sum + pnl, 0),
    winRate: priced.length ? (wins / priced.length) * 100 : 0,
    knownResultCount: priced.length,
    averageRr: averageRrFromTrades(trades),
    profitFactor: computeProfitFactor(trades),
    tradesTaken: trades.length,
    bestDayLabel: sameDay ? null : bestDay.label,
    bestDayPnl: sameDay ? null : bestDay.pnl,
    worstDayLabel: sameDay ? null : worstDay.label,
    worstDayPnl: sameDay ? null : worstDay.pnl,
    bestSessionLabel: bestSession.label,
    bestSessionPnl: bestSession.pnl,
    worstSessionLabel: worstSession.label,
    worstSessionPnl: worstSession.pnl,
    mostTradedSymbol: mostTradedSymbol(trades),
    averageHoldTimeSeconds: averageHoldSeconds(trades),
  }
}

function buildExecutiveSummary(
  metrics: TradingReportMetrics,
  kind: TradingReport["kind"],
  partial: boolean,
  comparisonNote: string | null,
  changedNote: string | null = null
): string {
  const periodLabel = kind === "weekly" ? "week" : "month"
  const partialLabel = partial ? "partial " : ""

  if (metrics.tradesTaken === 0) {
    return `No trades were logged during this ${partialLabel}${periodLabel}.`
  }

  if (metrics.knownResultCount === 0) {
    return `${metrics.tradesTaken} trade${metrics.tradesTaken === 1 ? "" : "s"} were logged this ${partialLabel}${periodLabel}, but none have a P&L yet.`
  }

  const tone =
    metrics.netPnl > 0 ? "positive" : metrics.netPnl < 0 ? "negative" : "flat"
  const priced =
    metrics.knownResultCount === metrics.tradesTaken
      ? `${metrics.tradesTaken} trade${metrics.tradesTaken === 1 ? "" : "s"}`
      : `${metrics.knownResultCount} priced trade${metrics.knownResultCount === 1 ? "" : "s"} of ${metrics.tradesTaken}`
  const winRate =
    metrics.knownResultCount >= COMPARATIVE_MIN_PER_SIDE
      ? ` Win rate was ${metrics.winRate.toFixed(1)}%.`
      : ""
  const comparison = comparisonNote ? ` ${comparisonNote}` : ""
  const changed = changedNote ? ` ${changedNote}` : ""
  return `This ${partialLabel}${periodLabel} was ${tone}: ${formatPnlCurrency(metrics.netPnl)} across ${priced}.${winRate}${comparison}${changed}`
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
      `${metrics.bestSessionLabel} was ahead of your other sessions (${formatPnlCurrency(metrics.bestSessionPnl)}).`
    )
  }

  if (metrics.profitFactor != null && metrics.profitFactor >= 1.5 && metrics.knownResultCount >= COMPARATIVE_MIN_PER_SIDE) {
    strengths.push(
      `Profit factor was ${metrics.profitFactor.toFixed(2)}.`
    )
  }

  if (
    comparisonTrades &&
    knownResults(comparisonTrades).length >= COMPARATIVE_MIN_PER_SIDE &&
    metrics.knownResultCount >= COMPARATIVE_MIN_PER_SIDE
  ) {
    const priorRr = averageRrFromTrades(comparisonTrades)
    if (
      metrics.averageRr != null &&
      priorRr != null &&
      priorRr !== 0 &&
      metrics.averageRr > priorRr * 1.05
    ) {
      const pct = Math.round(((metrics.averageRr - priorRr) / Math.abs(priorRr)) * 100)
      strengths.push(
        `Average R was ${pct}% higher than the same window in the prior period.`
      )
    }
  }

  const strategies = [...computeStrategyPnl(trades).entries()].filter(
    ([, row]) => row.count >= COMPARATIVE_MIN_PER_SIDE && row.pnl > 0
  )
  if (strategies.length >= 2) {
    strategies.sort((a, b) => b[1].pnl - a[1].pnl)
    const [name, row] = strategies[0]
    strengths.push(`${name} was your strongest tagged setup (${formatPnlCurrency(row.pnl)}).`)
  }

  return strengths.slice(0, 3)
}

function buildOpportunities(trades: any[], metrics: TradingReportMetrics): string[] {
  const opportunities: string[] = []

  if (
    metrics.worstSessionLabel &&
    metrics.worstSessionPnl != null &&
    metrics.worstSessionPnl < 0 &&
    metrics.worstSessionLabel !== metrics.bestSessionLabel
  ) {
    opportunities.push(
      `${metrics.worstSessionLabel} was behind your other sessions (${formatPnlCurrency(metrics.worstSessionPnl)}).`
    )
  }

  const hourly = computeHourlyPnl(trades)
  let morning = { pnl: 0, count: 0 }
  let afternoon = { pnl: 0, count: 0 }
  for (const [hour, row] of hourly) {
    if (hour >= 12) {
      afternoon.pnl += row.pnl
      afternoon.count += row.count
    } else {
      morning.pnl += row.pnl
      morning.count += row.count
    }
  }
  if (
    morning.count >= COMPARATIVE_MIN_PER_SIDE &&
    afternoon.count >= COMPARATIVE_MIN_PER_SIDE &&
    afternoon.pnl < morning.pnl &&
    afternoon.pnl < 0
  ) {
    opportunities.push("Afternoon results were weaker than the morning.")
  }

  const weekdays = [...computeWeekdayPnl(trades).entries()].filter(
    ([, row]) => row.count >= COMPARATIVE_MIN_PER_SIDE
  )
  if (weekdays.length >= 2) {
    weekdays.sort((a, b) => a[1].pnl - b[1].pnl)
    const [day, row] = weekdays[0]
    if (row.pnl < 0) {
      opportunities.push(
        `${WEEKDAY_LABELS[day]} was the weakest weekday with at least ${COMPARATIVE_MIN_PER_SIDE} priced trades (${formatPnlCurrency(row.pnl)}).`
      )
    }
  }

  if (
    metrics.averageRr != null &&
    metrics.averageRr < 1 &&
    metrics.knownResultCount >= COMPARATIVE_MIN_PER_SIDE
  ) {
    opportunities.push(`Average R was ${formatRR(metrics.averageRr)}.`)
  }

  if (
    metrics.profitFactor != null &&
    metrics.profitFactor < 1 &&
    metrics.knownResultCount >= COMPARATIVE_MIN_PER_SIDE
  ) {
    opportunities.push(
      `Profit factor was ${metrics.profitFactor.toFixed(2)}. Losses exceeded gains.`
    )
  }

  const hourlyRows = [...hourly.entries()].filter(
    ([, row]) => row.count >= COMPARATIVE_MIN_PER_SIDE
  )
  if (hourlyRows.length >= 2) {
    hourlyRows.sort((a, b) => a[1].pnl - b[1].pnl)
    const [hour, row] = hourlyRows[0]
    if (row.pnl < 0) {
      opportunities.push(
        `${formatHourLabel(hour)} Eastern was the weakest hour with at least ${COMPARATIVE_MIN_PER_SIDE} priced trades.`
      )
    }
  }

  return opportunities.slice(0, 5)
}

function buildRecommendations(adjustment: string | null): string[] {
  return adjustment ? [adjustment] : []
}

function buildKeyTakeaway(
  metrics: TradingReportMetrics,
  adjustment: string | null,
  kind: TradingReport["kind"]
): string {
  const periodLabel = kind === "weekly" ? "week" : "month"
  if (metrics.tradesTaken === 0) {
    return `No trades were logged this ${periodLabel}.`
  }
  if (metrics.knownResultCount === 0) {
    return "P&L is missing on these trades, so this report does not estimate a result."
  }
  if (adjustment) return adjustment
  return `${formatPnlCurrency(metrics.netPnl)} across ${metrics.knownResultCount} priced trades. No other pattern cleared the sample minimum.`
}

function whatChanged(
  metrics: TradingReportMetrics,
  priorTrades: any[] | null
): string | null {
  if (!priorTrades) return null
  if (
    metrics.knownResultCount < COMPARATIVE_MIN_PER_SIDE ||
    knownResults(priorTrades).length < COMPARATIVE_MIN_PER_SIDE
  ) {
    return null
  }
  const prior = buildMetrics(priorTrades)
  const delta = metrics.netPnl - prior.netPnl
  if (delta === 0) return "Net P&L matched the same window in the prior period."
  const direction = delta > 0 ? "higher" : "lower"
  return `Compared with the same window in the prior period, net P&L was ${formatPnlCurrency(Math.abs(delta))} ${direction}.`
}

function ruleAdjustment(trades: any[], context: PreferenceRuleContext | null): string | null {
  if (!context) return null
  const rows = trades.flatMap((trade) => {
    const row = complianceTradeFromRow(trade)
    return row ? [row] : []
  })
  return primaryRuleAdjustment(evaluatePreferenceCompliance(rows, context))
}

function findBestTrade(trades: any[]): any | null {
  let best: any | null = null
  let bestPnl = -Infinity
  for (const trade of trades) {
    const pnl = knownPnl(trade.pnl)
    if (pnl == null || pnl <= 0) continue
    if (pnl > bestPnl) {
      best = trade
      bestPnl = pnl
    }
  }
  return best
}


function comparisonAvailabilityNote(
  currentTrades: any[],
  priorTrades: any[] | null
): string | null {
  if (!priorTrades) return null
  if (
    knownResults(currentTrades).length >= COMPARATIVE_MIN_PER_SIDE &&
    knownResults(priorTrades).length >= COMPARATIVE_MIN_PER_SIDE
  ) {
    return null
  }
  return "A same-window comparison with the prior period is not available yet."
}

/** Report for an arbitrary trade set (e.g. Backtest Lab filtered pool). */
export function generateTradingReportForTrades(
  trades: any[],
  meta: {
    title: string
    dateRangeLabel: string
    kind?: TradingReport["kind"]
  }
): TradingReport {
  const metrics = buildMetrics(trades)
  const strengths = buildStrengths(trades, metrics, null)
  const adjustment = ruleAdjustment(trades, null) ?? buildOpportunities(trades, metrics)[0] ?? null
  const recommendations = buildRecommendations(adjustment)
  const bestTrade = findBestTrade(trades)
  const kind = meta.kind ?? "monthly"
  const now = new Date()

  return {
    periodKey: "monthly_this",
    kind,
    title: meta.title,
    dateRangeLabel: meta.dateRangeLabel,
    periodStartIso: now.toISOString(),
    periodEndIso: now.toISOString(),
    generatedAt: Date.now(),
    executiveSummary: buildExecutiveSummary(metrics, kind, false, null),
    metrics,
    strengths,
    opportunities: [],
    recommendations,
    bestTradeId: bestTrade?.id != null ? String(bestTrade.id) : null,
    keyTakeaway: buildKeyTakeaway(metrics, adjustment, kind),
    summarySource: "deterministic",
  }
}

export function generateTradingReport(
  trades: any[],
  periodKey: TradingReportPeriodKey,
  now = new Date(),
  context: PreferenceRuleContext | null = null
): TradingReport {
  return generateTradingReportFromBounds(
    trades,
    periodKey,
    getTradingReportPeriodBounds(periodKey, now),
    now,
    context
  )
}

/** Report for `week:YYYY-MM-DD`, including after that week is no longer "last week". */
export function generateTradingReportForWeek(
  trades: any[],
  mondayKey: string,
  now = new Date(),
  context: PreferenceRuleContext | null = null
): TradingReport | null {
  const monday = parseTradingReportWeekPeriodId(`week:${mondayKey}`)
  if (!monday) return null
  const bounds = absoluteTradingWeekBounds(monday, now)
  return generateTradingReportFromBounds(
    trades,
    bounds.key,
    bounds,
    now,
    context
  )
}

function generateTradingReportFromBounds(
  trades: any[],
  periodKey: TradingReportPeriodKey,
  bounds: TradingReportPeriodBounds,
  now: Date,
  context: PreferenceRuleContext | null
): TradingReport {
  const periodTrades = filterTradesForBounds(trades, bounds)
  const metrics = buildMetrics(periodTrades)
  const priorBounds = comparablePriorReportBounds(periodKey, now)
  const comparisonTrades = priorBounds
    ? filterTradesForBounds(trades, priorBounds)
    : null

  const strengths = buildStrengths(periodTrades, metrics, comparisonTrades)
  const adjustment =
    ruleAdjustment(periodTrades, context) ??
    buildOpportunities(periodTrades, metrics)[0] ??
    null
  const recommendations = buildRecommendations(adjustment)
  const bestTrade = findBestTrade(periodTrades)
  const note = comparisonAvailabilityNote(periodTrades, comparisonTrades)
  const changed = whatChanged(metrics, comparisonTrades)

  return {
    periodKey,
    kind: bounds.kind,
    title: tradingReportPeriodTitle(bounds.kind),
    dateRangeLabel: formatTradingReportDateRange(
      bounds.start,
      bounds.end,
      bounds.kind,
      bounds.partial
    ),
    periodStartIso: bounds.start.toISOString(),
    periodEndIso: bounds.end.toISOString(),
    generatedAt: Date.now(),
    executiveSummary: buildExecutiveSummary(metrics, bounds.kind, bounds.partial, note, changed),
    metrics,
    strengths,
    opportunities: [],
    recommendations,
    bestTradeId: bestTrade?.id != null ? String(bestTrade.id) : null,
    keyTakeaway: buildKeyTakeaway(metrics, adjustment, bounds.kind),
    summarySource: "deterministic",
  }
}

export function generateAllTradingReports(
  trades: any[],
  now = new Date(),
  context: PreferenceRuleContext | null = null
): Record<TradingReportPeriodKey, TradingReport> {
  return {
    weekly_this: generateTradingReport(trades, "weekly_this", now, context),
    weekly_last: generateTradingReport(trades, "weekly_last", now, context),
    monthly_this: generateTradingReport(trades, "monthly_this", now, context),
    monthly_last: generateTradingReport(trades, "monthly_last", now, context),
  }
}
