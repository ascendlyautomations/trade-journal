export type PerformanceWindow = "daily" | "weekly" | "monthly" | "yearly"

export type TradeSharePoolOptions = {
  selectedDate: string
  accountFilter: string
  accountTypeFilter: string
  resultFilter?: "all" | "wins" | "losses"
  /** Matches dashboard “Public Trades” narrowing */
  showPublicOnly?: boolean
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

    if (accountFilter !== "all") {
      const accountName = String(trade.account_name || "").trim()
      const size = String(trade.account_size || "").trim()
      const id = String(trade.account_id || "").trim()
      const accountKey = `${accountName}|${size}|${id}`
      if (accountKey !== accountFilter) return false
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
  now = new Date()
): any[] {
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
  avgRR: number
}

export function computePerformanceStats(trades: any[]): PerformanceStats {
  const totalTrades = trades.length
  const wins = trades.filter((t) => (Number(t.pnl) || 0) > 0).length
  const winRate = totalTrades ? (wins / totalTrades) * 100 : 0
  const totalPnL = trades.reduce((sum, t) => sum + (Number(t.pnl) || 0), 0)
  const avgRR =
    trades.reduce((sum, t) => sum + (Number(t.rr) || 0), 0) /
    (totalTrades || 1)
  return { totalTrades, wins, winRate, totalPnL, avgRR }
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
      return "Daily"
    case "weekly":
      return "Weekly"
    case "monthly":
      return "Monthly"
    case "yearly":
      return "Yearly"
    default:
      return w
  }
}

/**
 * Human-readable range for the performance share card date line (TradeShareCard parity).
 */
export function formatPerformanceShareDateRange(
  window: PerformanceWindow,
  filteredTrades: any[],
  now = new Date()
): string {
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
    default:
      return ""
  }
}
