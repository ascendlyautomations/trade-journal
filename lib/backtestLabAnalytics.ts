import {
  backtestStrategyGroupKey,
  BACKTEST_LAB_NO_STRATEGY,
  computeTradeExpectancy,
  type BacktestLabStrategyGroup,
} from "@/lib/backtestLabFilters"
import { normalizeFuturesSymbol } from "@/lib/normalizeFuturesSymbol"
import { computePeriodTradeStats } from "@/lib/periodTradeStats"

export type BacktestLabGroupStats = {
  key: string
  label: string
  totalTrades: number
  winRate: number | null
  netPnl: number
  profitFactor: number | null
  profitFactorInfinite: boolean
  expectancy: number | null
  avgRR: number | null
  avgWin: number | null
  avgLoss: number | null
}

export type BacktestLabSortKey =
  | "label"
  | "totalTrades"
  | "winRate"
  | "netPnl"
  | "profitFactor"
  | "expectancy"
  | "avgRR"
  | "avgWin"
  | "avgLoss"

export type BacktestLabSortDirection = "asc" | "desc"

function instrumentGroupKey(value: unknown): string {
  const raw = String(value ?? "").trim()
  if (!raw) return ""
  return normalizeFuturesSymbol(raw) || raw.toUpperCase()
}

function pickInstrumentLabel(
  trades: readonly { ticker?: unknown }[],
  key: string
): string {
  const counts = new Map<string, number>()
  for (const trade of trades) {
    if (instrumentGroupKey(trade.ticker) !== key) continue
    const raw = String(trade.ticker ?? "").trim().toUpperCase() || key
    counts.set(raw, (counts.get(raw) ?? 0) + 1)
  }
  let best = key
  let bestCount = -1
  for (const [label, count] of counts) {
    if (count > bestCount) {
      bestCount = count
      best = label
    }
  }
  return best
}

function statsForTrades(
  trades: readonly Record<string, unknown>[],
  key: string,
  label: string
): BacktestLabGroupStats {
  const period = computePeriodTradeStats(trades)
  return {
    key,
    label,
    totalTrades: period.totalTrades,
    winRate: period.winRate,
    netPnl: period.totalPnl,
    profitFactor: period.profitFactor,
    profitFactorInfinite: period.profitFactorInfinite,
    expectancy: computeTradeExpectancy(trades),
    avgRR: period.avgRR,
    avgWin: period.avgWin,
    avgLoss: period.avgLoss,
  }
}

export function buildBacktestStrategyLeaderboard(
  trades: readonly Record<string, unknown>[],
  groups?: BacktestLabStrategyGroup[]
): BacktestLabGroupStats[] {
  const byKey = new Map<string, Record<string, unknown>[]>()

  for (const trade of trades) {
    const key = backtestStrategyGroupKey(trade.strategy)
    if (!byKey.has(key)) byKey.set(key, [])
    byKey.get(key)!.push(trade)
  }

  const labelByKey = new Map<string, string>()
  if (groups) {
    for (const group of groups) labelByKey.set(group.key, group.label)
  }

  const rows: BacktestLabGroupStats[] = []
  for (const [key, bucket] of byKey) {
    const label =
      labelByKey.get(key) ??
      (key === BACKTEST_LAB_NO_STRATEGY ? "No Strategy" : key)
    rows.push(statsForTrades(bucket, key, label))
  }

  return rows
}

export function buildBacktestInstrumentLeaderboard(
  trades: readonly Record<string, unknown>[]
): BacktestLabGroupStats[] {
  const byKey = new Map<string, Record<string, unknown>[]>()

  for (const trade of trades) {
    const key = instrumentGroupKey(trade.ticker)
    if (!key) continue
    if (!byKey.has(key)) byKey.set(key, [])
    byKey.get(key)!.push(trade)
  }

  const rows: BacktestLabGroupStats[] = []
  for (const [key, bucket] of byKey) {
    rows.push(
      statsForTrades(bucket, key, pickInstrumentLabel(trades, key))
    )
  }

  return rows
}

function sortableNumber(value: number | null | undefined): number | null {
  if (value == null || !Number.isFinite(value)) return null
  return value
}

export function sortBacktestLabGroupStats(
  rows: readonly BacktestLabGroupStats[],
  sortKey: BacktestLabSortKey,
  direction: BacktestLabSortDirection
): BacktestLabGroupStats[] {
  const factor = direction === "asc" ? 1 : -1

  const valueFor = (row: BacktestLabGroupStats): number | null => {
    switch (sortKey) {
      case "label":
        return null
      case "totalTrades":
        return row.totalTrades
      case "winRate":
        return sortableNumber(row.winRate)
      case "netPnl":
        return row.netPnl
      case "profitFactor":
        if (row.profitFactorInfinite) return Number.POSITIVE_INFINITY
        return sortableNumber(row.profitFactor)
      case "expectancy":
        return sortableNumber(row.expectancy)
      case "avgRR":
        return sortableNumber(row.avgRR)
      case "avgWin":
        return sortableNumber(row.avgWin)
      case "avgLoss":
        return sortableNumber(row.avgLoss)
      default:
        return null
    }
  }

  return [...rows].sort((a, b) => {
    if (sortKey === "label") {
      return factor * a.label.localeCompare(b.label)
    }
    const av = valueFor(a)
    const bv = valueFor(b)
    if (av == null && bv == null) return a.label.localeCompare(b.label)
    if (av == null) return 1
    if (bv == null) return -1
    if (av === bv) return a.label.localeCompare(b.label)
    return av > bv ? factor : -factor
  })
}

export type BacktestLabComparisonMetric =
  | "netPnl"
  | "winRate"
  | "profitFactor"
  | "avgRR"
  | "expectancy"

export function buildStrategyComparisonChartData(
  rows: readonly BacktestLabGroupStats[],
  metric: BacktestLabComparisonMetric,
  maxStrategies = 8
): Array<{ name: string; value: number; key: string }> {
  const sorted = sortBacktestLabGroupStats(rows, "netPnl", "desc").slice(
    0,
    maxStrategies
  )

  return sorted
    .map((row) => {
      let value: number | null = null
      switch (metric) {
        case "netPnl":
          value = row.netPnl
          break
        case "winRate":
          value = row.winRate
          break
        case "profitFactor":
          value = row.profitFactorInfinite
            ? 999
            : row.profitFactor
          break
        case "avgRR":
          value = row.avgRR
          break
        case "expectancy":
          value = row.expectancy
          break
      }
      if (value == null || !Number.isFinite(value)) return null
      return { name: row.label, value, key: row.key }
    })
    .filter((row): row is { name: string; value: number; key: string } =>
      Boolean(row)
    )
}
