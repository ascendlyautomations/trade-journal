import { averageRrFromTrades } from "./tradeRr"
import {
  accountRowForTrade,
  tradeMatchesAccountFilter,
} from "./tradeAccountDisplay"

export type PerformanceWindow =
  | "daily"
  | "weekly"
  | "monthly"
  | "yearly"
  | "custom"

export type PerformanceWindowOptions = {
  now?: Date
  customRangeStart?: string
  customRangeEnd?: string
}

export type TradeSharePoolOptions = {
  selectedDate: string
  accountFilter: string
  accountTypeFilter: string
  resultFilter?: "all" | "wins" | "losses"
  /** Matches dashboard “Public Trades” narrowing */
  showPublicOnly?: boolean
  accountById?: Record<
    string,
    { name?: string | null; account_size?: string | null; is_active?: boolean | null }
  > | null
}

function tradeIsPublic(t: any): boolean {
  if (t?.is_public === true) return true
  const desc = t?.public_description
  return typeof desc === "string" && desc.trim().length > 0
}

/**
 * Trades eligible for performance share / stats — same as list filters except **no** timeframe window.
 */
export function filterTradesForPerformanceSharePool(
  trades: any[],
  opts: TradeSharePoolOptions
): any[] {
  const {
    selectedDate,
    accountFilter,
    accountTypeFilter,
    resultFilter = "all",
    showPublicOnly,
    accountById,
  } = opts

  let pool = trades.filter((trade) => {
    if (selectedDate) {
      const tradeDate = new Date(trade.created_at)
      const selected = new Date(selectedDate + "T00:00:00")
      if (
        tradeDate.getFullYear() !== selected.getFullYear() ||
        tradeDate.getMonth() !== selected.getMonth() ||
        tradeDate.getDate() !== selected.getDate()
      ) {
        return false
      }
    }

    if (resultFilter === "wins" && !(Number(trade.pnl) > 0)) return false
    if (resultFilter === "losses" && !(Number(trade.pnl) < 0)) return false

    if (
      !tradeMatchesAccountFilter(
        trade,
        accountFilter,
        accountRowForTrade(trade, accountById)
      )
    ) {
      return false
    }

    const tradeMode = String(trade.mode ?? trade.account_type ?? "")
      .toLowerCase()
      .trim()
    const selectedAcct = accountTypeFilter.toLowerCase().trim()
    if (accountTypeFilter !== "all") {
      if (tradeMode !== selectedAcct) return false
    }

    return true
  })

  if (showPublicOnly) {
    const pub = pool.filter(tradeIsPublic)
    pool = pub.length > 0 ? pub : pool
  }

  return pool
}

export function filterTradesByPerformanceWindow(
  trades: any[],
  window: PerformanceWindow,
  options: PerformanceWindowOptions = {}
): any[] {
  const now = options.now ?? new Date()
  const customStart = options.customRangeStart?.trim() ?? ""
  const customEnd = options.customRangeEnd?.trim() ?? ""

  return trades.filter((trade) => {
    const tradeDate = new Date(trade.created_at)
    if (Number.isNaN(tradeDate.getTime())) return false

    switch (window) {
      case "daily":
        return tradeDate.toDateString() === now.toDateString()
      case "weekly": {
        const weekAgo = new Date(now)
        weekAgo.setDate(now.getDate() - 7)
        return tradeDate >= weekAgo
      }
      case "monthly":
        return (
          tradeDate.getMonth() === now.getMonth() &&
          tradeDate.getFullYear() === now.getFullYear()
        )
      case "yearly":
        return tradeDate.getFullYear() === now.getFullYear()
      case "custom": {
        if (!customStart || !customEnd) return true
        const start = new Date(`${customStart}T00:00:00`)
        const end = new Date(`${customEnd}T23:59:59.999`)
        if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
          return true
        }
        return tradeDate >= start && tradeDate <= end
      }
      default:
        return true
    }
  })
}

export type PerformanceStats = {
  totalTrades: number
  wins: number
  winRate: number
  totalPnL: number
  avgRR: number | null
  /** Mean hold time in seconds (filtered trades with duration data only). */
  avgDurationSeconds: number | null
  /** Ticker symbol appearing most often in the filtered set. */
  mostTradedTicker: string | null
}

function resolveTradeDurationSeconds(trade: any): number | null {
  const stored = Number(trade.duration_seconds)
  if (Number.isFinite(stored) && stored > 0) return Math.round(stored)

  const entry = trade.entry_time ?? null
  const exit = trade.exit_time ?? null
  if (entry && exit) {
    const diff = +new Date(String(exit)) - +new Date(String(entry))
    if (Number.isFinite(diff) && diff > 0) return Math.floor(diff / 1000)
  }

  return null
}

function computeMostTradedTicker(trades: any[]): string | null {
  const counts = new Map<string, number>()

  for (const trade of trades) {
    const raw = trade.ticker != null ? String(trade.ticker).trim() : ""
    if (!raw) continue
    const key = raw.toUpperCase()
    counts.set(key, (counts.get(key) ?? 0) + 1)
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

export function computePerformanceStats(trades: any[]): PerformanceStats {
  const totalTrades = trades.length
  const wins = trades.filter((t) => (Number(t.pnl) || 0) > 0).length
  const winRate = totalTrades ? (wins / totalTrades) * 100 : 0
  const totalPnL = trades.reduce((sum, t) => sum + (Number(t.pnl) || 0), 0)
  const avgRR = averageRrFromTrades(trades)

  const durations = trades
    .map(resolveTradeDurationSeconds)
    .filter((seconds): seconds is number => seconds != null)

  const avgDurationSeconds =
    durations.length > 0
      ? Math.round(
          durations.reduce((sum, seconds) => sum + seconds, 0) /
            durations.length
        )
      : null

  const mostTradedTicker = computeMostTradedTicker(trades)

  return {
    totalTrades,
    wins,
    winRate,
    totalPnL,
    avgRR,
    avgDurationSeconds,
    mostTradedTicker,
  }
}

/** Point for cumulative P&amp;L curve (sorted by trade time; starts at 0 equity). */
export type EquityCurvePoint = { step: number; equity: number }

/**
 * Chronological cumulative P&amp;L from trades in the selected window.
 * Leading point at equity 0 anchors the curve; empty input yields a flat zero segment.
 */
export function buildEquityCurveFromTrades(trades: any[]): EquityCurvePoint[] {
  if (!trades?.length) {
    return [
      { step: 0, equity: 0 },
      { step: 1, equity: 0 },
    ]
  }

  const sorted = [...trades].sort(
    (a, b) =>
      new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
  )

  const points: EquityCurvePoint[] = [{ step: 0, equity: 0 }]
  let cum = 0
  sorted.forEach((t, i) => {
    cum += Number(t.pnl) || 0
    points.push({ step: i + 1, equity: cum })
  })
  return points
}

export function performanceWindowLabel(w: PerformanceWindow): string {
  switch (w) {
    case "daily":
      return "Today"
    case "weekly":
      return "This Week"
    case "monthly":
      return "This Month"
    case "yearly":
      return "This Year"
    case "custom":
      return "Custom"
    default:
      return w
  }
}

/**
 * Start/end dates for the performance share card range line (en-US format applied in UI).
 */
export function getPerformanceShareRangeBounds(
  window: PerformanceWindow,
  filteredTrades: any[],
  options: PerformanceWindowOptions = {}
): { start: Date; end: Date } | null {
  const now = options.now ?? new Date()
  const customStart = options.customRangeStart?.trim() ?? ""
  const customEnd = options.customRangeEnd?.trim() ?? ""

  const dates = filteredTrades
    .map((t) => new Date(t.created_at))
    .filter((d) => !Number.isNaN(d.getTime()))

  if (dates.length > 0) {
    const minT = Math.min(...dates.map((d) => d.getTime()))
    const maxT = Math.max(...dates.map((d) => d.getTime()))
    return { start: new Date(minT), end: new Date(maxT) }
  }

  if (window === "custom" && customStart && customEnd) {
    const start = new Date(`${customStart}T00:00:00`)
    const end = new Date(`${customEnd}T23:59:59.999`)
    if (!Number.isNaN(start.getTime()) && !Number.isNaN(end.getTime())) {
      return { start, end }
    }
  }

  switch (window) {
    case "daily": {
      const start = new Date(now)
      start.setHours(0, 0, 0, 0)
      const end = new Date(start)
      end.setHours(23, 59, 59, 999)
      return { start, end }
    }
    case "weekly": {
      const start = new Date(now)
      start.setDate(now.getDate() - 7)
      return { start, end: new Date(now) }
    }
    case "monthly": {
      const start = new Date(now.getFullYear(), now.getMonth(), 1)
      const end = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59, 999)
      return { start, end }
    }
    case "yearly": {
      const start = new Date(now.getFullYear(), 0, 1)
      const end = new Date(now.getFullYear(), 11, 31, 23, 59, 59, 999)
      return { start, end }
    }
    case "custom":
      return null
    default:
      return null
  }
}

/**
 * Human-readable range for the performance share card date line (TradeShareCard parity).
 */
export function formatPerformanceShareDateRange(
  window: PerformanceWindow,
  filteredTrades: any[],
  options: PerformanceWindowOptions = {}
): string {
  const now = options.now ?? new Date()
  const customStart = options.customRangeStart?.trim() ?? ""
  const customEnd = options.customRangeEnd?.trim() ?? ""

  if (filteredTrades.length > 0) {
    const dates = filteredTrades
      .map((t) => new Date(t.created_at))
      .filter((d) => !Number.isNaN(d.getTime()))
    if (dates.length > 0) {
      const minT = Math.min(...dates.map((d) => d.getTime()))
      const maxT = Math.max(...dates.map((d) => d.getTime()))
      const min = new Date(minT)
      const max = new Date(maxT)
      if (min.toDateString() === max.toDateString()) {
        return min.toLocaleDateString(undefined, {
          month: "short",
          day: "numeric",
          year: "numeric",
        })
      }
      return `${min.toLocaleDateString(undefined, {
        month: "short",
        day: "numeric",
      })} – ${max.toLocaleDateString(undefined, {
        month: "short",
        day: "numeric",
        year: "numeric",
      })}`
    }
  }

  switch (window) {
    case "daily":
      return now.toLocaleDateString(undefined, {
        month: "short",
        day: "numeric",
        year: "numeric",
      })
    case "weekly": {
      const start = new Date(now)
      start.setDate(now.getDate() - 7)
      return `${start.toLocaleDateString(undefined, {
        month: "short",
        day: "numeric",
      })} – ${now.toLocaleDateString(undefined, {
        month: "short",
        day: "numeric",
        year: "numeric",
      })}`
    }
    case "monthly":
      return now.toLocaleDateString(undefined, {
        month: "long",
        year: "numeric",
      })
    case "yearly":
      return String(now.getFullYear())
    case "custom": {
      if (customStart && customEnd) {
        const start = new Date(`${customStart}T00:00:00`)
        const end = new Date(`${customEnd}T23:59:59.999`)
        if (!Number.isNaN(start.getTime()) && !Number.isNaN(end.getTime())) {
          return `${start.toLocaleDateString(undefined, {
            month: "short",
            day: "numeric",
          })} – ${end.toLocaleDateString(undefined, {
            month: "short",
            day: "numeric",
            year: "numeric",
          })}`
        }
      }
      return "Custom range"
    }
    default:
      return ""
  }
}
