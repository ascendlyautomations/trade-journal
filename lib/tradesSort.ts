/** Presentation-only sort keys for the native iOS Trades filter sheet. */
export type TradesSortKey =
  | "newest"
  | "oldest"
  | "pnl_high"
  | "pnl_low"
  | "rr_high"
  | "rr_low"

export const TRADES_SORT_OPTIONS: { key: TradesSortKey; label: string }[] = [
  { key: "newest", label: "Newest" },
  { key: "oldest", label: "Oldest" },
  { key: "pnl_high", label: "Highest P&L" },
  { key: "pnl_low", label: "Lowest P&L" },
  { key: "rr_high", label: "Highest RR" },
  { key: "rr_low", label: "Lowest RR" },
]

function tradeTimeMs(trade: { created_at?: string | null }): number {
  const t = trade.created_at ? new Date(trade.created_at).getTime() : 0
  return Number.isFinite(t) ? t : 0
}

function tradePnl(trade: { pnl?: number | null }): number {
  return Number(trade.pnl) || 0
}

function tradeRr(trade: { rr?: unknown }): number | null {
  if (trade.rr == null || trade.rr === "") return null
  const n = Number(trade.rr)
  return Number.isFinite(n) ? n : null
}

/** Sort a copy of trades for display only — does not mutate source data. */
export function sortTradesForDisplay<T extends { created_at?: string | null; pnl?: number | null; rr?: unknown }>(
  trades: T[],
  sortBy: TradesSortKey
): T[] {
  const list = trades.slice()
  switch (sortBy) {
    case "oldest":
      return list.sort((a, b) => tradeTimeMs(a) - tradeTimeMs(b))
    case "pnl_high":
      return list.sort((a, b) => tradePnl(b) - tradePnl(a))
    case "pnl_low":
      return list.sort((a, b) => tradePnl(a) - tradePnl(b))
    case "rr_high":
      return list.sort((a, b) => {
        const ar = tradeRr(a)
        const br = tradeRr(b)
        if (ar == null && br == null) return 0
        if (ar == null) return 1
        if (br == null) return -1
        return br - ar
      })
    case "rr_low":
      return list.sort((a, b) => {
        const ar = tradeRr(a)
        const br = tradeRr(b)
        if (ar == null && br == null) return 0
        if (ar == null) return 1
        if (br == null) return -1
        return ar - br
      })
    case "newest":
    default:
      return list.sort((a, b) => tradeTimeMs(b) - tradeTimeMs(a))
  }
}
