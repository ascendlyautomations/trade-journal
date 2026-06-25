export type TradePointsSource = {
  points?: unknown
  entry_price?: unknown
  exit_price?: unknown
  direction?: unknown
}

/** True when the trade row has an explicit numeric points value (including 0). */
export function hasStoredTradePoints(value: unknown): boolean {
  if (value === null || value === undefined || value === "") return false
  return Number.isFinite(Number(value))
}

function directionIsShort(direction: string): boolean {
  const s = String(direction ?? "").trim().toLowerCase()
  if (!s) return false
  if (s === "short" || s === "sell" || s === "ss" || s === "bear") return true
  if (/\bshort\b/.test(s) || /\bsell\b/.test(s)) return true
  return false
}

/** Long: exit − entry; Short: entry − exit (negative when the trade loses). */
export function calculateDirectionalPoints(
  direction: string,
  entryPrice: number,
  exitPrice: number
): number {
  if (directionIsShort(direction)) return entryPrice - exitPrice
  return exitPrice - entryPrice
}

function inferTradeDirection(trade: TradePointsSource): string {
  const raw = trade.direction != null ? String(trade.direction).trim() : ""
  if (raw) return raw

  const entry = Number(trade.entry_price)
  const exit = Number(trade.exit_price)
  if (Number.isFinite(entry) && Number.isFinite(exit)) {
    return exit > entry ? "Long" : "Short"
  }
  return "Long"
}

/**
 * Prefer stored `points` from the database (CSV import or manual entry).
 * When missing, derive from entry/exit prices and direction.
 */
export function resolveTradePoints(
  trade: TradePointsSource | null | undefined
): number | null {
  if (!trade) return null

  if (hasStoredTradePoints(trade.points)) {
    return Number(trade.points)
  }

  const entry = Number(trade.entry_price)
  const exit = Number(trade.exit_price)
  if (!Number.isFinite(entry) || !Number.isFinite(exit)) return null

  return calculateDirectionalPoints(inferTradeDirection(trade), entry, exit)
}
