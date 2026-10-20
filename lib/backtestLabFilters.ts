import { getDashboardTradingDayKey } from "@/lib/dashboardTradeDate"
import { normalizeFuturesSymbol } from "@/lib/normalizeFuturesSymbol"
import { isBacktestTrade } from "@/lib/tradeModeFilters"
import type {
  BacktestLabDocumentationFilter,
  BacktestLabReviewFilter,
} from "@/lib/backtestLabReview"

export type BacktestLabResultFilter = "all" | "wins" | "losses"

export type BacktestLabFilterState = {
  accountId: string
  strategy: string
  ticker: string
  dateStart: string
  dateEnd: string
  result: BacktestLabResultFilter
  review: BacktestLabReviewFilter
  documentation: BacktestLabDocumentationFilter
}

export type {
  BacktestLabDocumentationFilter,
  BacktestLabReviewFilter,
} from "@/lib/backtestLabReview"

function hasTradeText(value: unknown): boolean {
  return String(value ?? "").trim().length > 0
}

function tradeMatchesReviewFilter(
  trade: Record<string, unknown>,
  review: BacktestLabReviewFilter
): boolean {
  if (review === "all") return true
  if (review === "reviewed") return trade.reviewed === true
  return trade.reviewed !== true
}

function tradeMatchesDocumentationFilter(
  trade: Record<string, unknown>,
  documentation: BacktestLabDocumentationFilter
): boolean {
  if (documentation === "all") return true
  const hasStrategy = hasTradeText(trade.strategy)
  const hasNotes =
    hasTradeText(trade.notes) ||
    hasTradeText(trade.top_confluences) ||
    hasTradeText(trade.psychology_notes) ||
    hasTradeText(trade.public_description)
  const hasScreenshot = hasTradeText(trade.image_url)
  return !hasStrategy || !hasNotes || !hasScreenshot
}

export const BACKTEST_LAB_FILTER_ALL = "all" as const
export const BACKTEST_LAB_NO_STRATEGY = "__none__" as const

/** Backtest Lab date filters are `YYYY-MM-DD` strings or empty. */
export function normalizeBacktestLabFilterDate(value: unknown): string {
  if (value == null) return ""
  if (typeof value === "object" && value !== null && "target" in value) {
    const target = (value as { target?: { value?: unknown } }).target
    return normalizeBacktestLabFilterDate(target?.value)
  }
  if (value instanceof Date) {
    if (Number.isNaN(value.getTime())) return ""
    const y = value.getFullYear()
    const m = String(value.getMonth() + 1).padStart(2, "0")
    const d = String(value.getDate()).padStart(2, "0")
    return `${y}-${m}-${d}`
  }
  const raw = typeof value === "string" ? value.trim() : String(value).trim()
  if (!raw || raw.startsWith("[object ")) return ""
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) return raw
  return ""
}

function backtestLabFilterDateBounds(filters: BacktestLabFilterState): {
  dateStart: string
  dateEnd: string
} {
  return {
    dateStart: normalizeBacktestLabFilterDate(filters.dateStart),
    dateEnd: normalizeBacktestLabFilterDate(filters.dateEnd),
  }
}

export type BacktestLabStrategyGroup = {
  /** Stable filter key (lowercase trimmed, or {@link BACKTEST_LAB_NO_STRATEGY}). */
  key: string
  /** Preferred display label from the most common stored spelling. */
  label: string
}

export function selectBacktestTrades<T extends Parameters<typeof isBacktestTrade>[0]>(
  rows: readonly T[]
): T[] {
  return rows.filter((row) => isBacktestTrade(row))
}

/** Grouping key for strategy filters and analytics (does not mutate stored values). */
export function backtestStrategyGroupKey(value: unknown): string {
  const trimmed = String(value ?? "").trim()
  if (!trimmed) return BACKTEST_LAB_NO_STRATEGY
  return trimmed.toLowerCase()
}

function normalizedStrategy(value: unknown): string {
  return String(value ?? "").trim()
}

function strategyMatchesFilter(
  trade: { strategy?: unknown },
  filterStrategy: string
): boolean {
  if (filterStrategy === BACKTEST_LAB_FILTER_ALL) return true
  const key = backtestStrategyGroupKey(trade.strategy)
  if (filterStrategy === BACKTEST_LAB_NO_STRATEGY) {
    return key === BACKTEST_LAB_NO_STRATEGY
  }
  return key === filterStrategy
}

function normalizedTicker(value: unknown): string {
  const raw = String(value ?? "").trim()
  if (!raw) return ""
  return normalizeFuturesSymbol(raw) || raw.toUpperCase()
}

export function distinctBacktestStrategyGroups(
  trades: readonly { strategy?: unknown }[]
): BacktestLabStrategyGroup[] {
  const labelCounts = new Map<string, Map<string, number>>()

  for (const trade of trades) {
    const raw = normalizedStrategy(trade.strategy)
    const key = backtestStrategyGroupKey(trade.strategy)
    if (!labelCounts.has(key)) labelCounts.set(key, new Map())
    const counts = labelCounts.get(key)!
    counts.set(raw || "No Strategy", (counts.get(raw || "No Strategy") ?? 0) + 1)
  }

  const groups: BacktestLabStrategyGroup[] = []
  for (const [key, counts] of labelCounts) {
    let bestLabel = key === BACKTEST_LAB_NO_STRATEGY ? "No Strategy" : key
    let bestCount = -1
    for (const [label, count] of counts) {
      if (count > bestCount) {
        bestCount = count
        bestLabel = label
      }
    }
    groups.push({ key, label: bestLabel })
  }

  return groups.sort((a, b) => a.label.localeCompare(b.label))
}

/** @deprecated Use {@link distinctBacktestStrategyGroups} labels for UI only. */
export function distinctBacktestStrategies(
  trades: readonly { strategy?: unknown }[]
): string[] {
  return distinctBacktestStrategyGroups(trades)
    .filter((g) => g.key !== BACKTEST_LAB_NO_STRATEGY)
    .map((g) => g.label)
}

export function distinctBacktestTickers(
  trades: readonly { ticker?: unknown }[]
): string[] {
  const seen = new Set<string>()
  for (const trade of trades) {
    const t = normalizedTicker(trade.ticker)
    if (t) seen.add(t)
  }
  return Array.from(seen).sort((a, b) => a.localeCompare(b))
}

export type ApplyBacktestLabFiltersOptions = {
  /** When true, ignore the strategy filter (for cross-strategy analytics). */
  omitStrategy?: boolean
}

export function applyBacktestLabFilters<T extends Record<string, unknown>>(
  trades: readonly T[],
  filters: BacktestLabFilterState,
  options?: ApplyBacktestLabFiltersOptions
): T[] {
  return trades.filter((trade) => {
    if (
      filters.accountId !== BACKTEST_LAB_FILTER_ALL &&
      String(trade.account_id ?? "") !== filters.accountId
    ) {
      return false
    }

    if (!options?.omitStrategy && !strategyMatchesFilter(trade, filters.strategy)) {
      return false
    }

    if (filters.ticker !== BACKTEST_LAB_FILTER_ALL) {
      if (normalizedTicker(trade.ticker) !== filters.ticker) return false
    }

    const dayKey = getDashboardTradingDayKey(trade)
    const { dateStart, dateEnd } = backtestLabFilterDateBounds(filters)
    if (dateStart || dateEnd) {
      if (!dayKey) return false
      if (dateStart && dayKey < dateStart) {
        return false
      }
      if (dateEnd && dayKey > dateEnd) {
        return false
      }
    }

    const pnl = Number(trade.pnl) || 0
    if (filters.result === "wins" && pnl <= 0) return false
    if (filters.result === "losses" && pnl >= 0) return false

    if (!tradeMatchesReviewFilter(trade, filters.review)) return false
    if (!tradeMatchesDocumentationFilter(trade, filters.documentation)) {
      return false
    }

    return true
  })
}

export function pickDefaultBacktestAccountId(
  accounts: readonly {
    id?: unknown
    category?: unknown
    mode?: unknown
    is_active?: boolean | null
    can_add_trades?: boolean | null
  }[]
): string | null {
  for (const account of accounts) {
    if (account.is_active === false || account.can_add_trades === false) continue
    const category = String(account.category ?? "").trim()
    const mode = String(account.mode ?? "").trim().toLowerCase()
    if (category === "Backtest" || mode === "backtest") {
      const id = String(account.id ?? "").trim()
      if (id) return id
    }
  }
  return null
}

/** Classic expectancy: winRate × avgWin − lossRate × avgLoss. */
export function formatBacktestLabFilterDateRangeLabel(
  filters: BacktestLabFilterState
): string {
  const { dateStart: start, dateEnd: end } = backtestLabFilterDateBounds(filters)
  if (start && end) return `${start} – ${end}`
  if (start) return `From ${start}`
  if (end) return `Through ${end}`
  return "All dates in current filter"
}

export function computeTradeExpectancy(
  trades: readonly { pnl?: unknown }[]
): number | null {
  if (!trades.length) return null
  const wins = trades.filter((t) => (Number(t.pnl) || 0) > 0)
  const losses = trades.filter((t) => (Number(t.pnl) || 0) < 0)
  const winRate = wins.length / trades.length
  const lossRate = losses.length / trades.length
  const avgWin =
    wins.length > 0
      ? wins.reduce((sum, t) => sum + (Number(t.pnl) || 0), 0) / wins.length
      : 0
  const avgLoss =
    losses.length > 0
      ? Math.abs(
          losses.reduce((sum, t) => sum + (Number(t.pnl) || 0), 0) /
            losses.length
        )
      : 0
  return winRate * avgWin - lossRate * avgLoss
}
