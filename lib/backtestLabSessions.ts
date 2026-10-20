import {
  backtestStrategyGroupKey,
  BACKTEST_LAB_NO_STRATEGY,
  type BacktestLabStrategyGroup,
} from "@/lib/backtestLabFilters"
import { getDashboardTradingDayKey } from "@/lib/dashboardTradeDate"
import { normalizeFuturesSymbol } from "@/lib/normalizeFuturesSymbol"
import { computePeriodTradeStats } from "@/lib/periodTradeStats"

export type BacktestLabSessionGroupMode = "date" | "strategy" | "instrument"

export type BacktestLabSessionGroup = {
  key: string
  label: string
  trades: Record<string, unknown>[]
  totalTrades: number
  netPnl: number
  winRate: number | null
  avgRR: number | null
}

function instrumentKey(ticker: unknown): string {
  const raw = String(ticker ?? "").trim()
  if (!raw) return ""
  return normalizeFuturesSymbol(raw) || raw.toUpperCase()
}

function groupKeyForTrade(
  trade: Record<string, unknown>,
  mode: BacktestLabSessionGroupMode,
  labelByStrategyKey: Map<string, string>
): { key: string; label: string } | null {
  if (mode === "date") {
    const day = getDashboardTradingDayKey(trade)
    if (!day) return null
    return { key: day, label: day }
  }
  if (mode === "strategy") {
    const key = backtestStrategyGroupKey(trade.strategy)
    const label =
      labelByStrategyKey.get(key) ??
      (key === BACKTEST_LAB_NO_STRATEGY ? "No Strategy" : key)
    return { key, label }
  }
  const key = instrumentKey(trade.ticker)
  if (!key) return null
  return { key, label: key }
}

export function buildBacktestLabSessionGroups(
  trades: readonly Record<string, unknown>[],
  mode: BacktestLabSessionGroupMode,
  strategyGroups?: readonly BacktestLabStrategyGroup[]
): BacktestLabSessionGroup[] {
  const labelByStrategyKey = new Map<string, string>()
  if (strategyGroups) {
    for (const group of strategyGroups) {
      labelByStrategyKey.set(group.key, group.label)
    }
  }

  const buckets = new Map<string, { label: string; trades: Record<string, unknown>[] }>()

  for (const trade of trades) {
    const meta = groupKeyForTrade(trade, mode, labelByStrategyKey)
    if (!meta) continue
    if (!buckets.has(meta.key)) {
      buckets.set(meta.key, { label: meta.label, trades: [] })
    }
    buckets.get(meta.key)!.trades.push(trade)
  }

  const rows: BacktestLabSessionGroup[] = []
  for (const [key, bucket] of buckets) {
    const stats = computePeriodTradeStats(bucket.trades)
    rows.push({
      key,
      label: bucket.label,
      trades: bucket.trades,
      totalTrades: stats.totalTrades,
      netPnl: stats.totalPnl,
      winRate: stats.winRate,
      avgRR: stats.avgRR,
    })
  }

  if (mode === "date") {
    return rows.sort((a, b) => b.key.localeCompare(a.key))
  }
  return rows.sort((a, b) => b.netPnl - a.netPnl || a.label.localeCompare(b.label))
}
