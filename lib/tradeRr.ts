/** RR storage and analytics helpers — missing RR is null, not 0. */

/** Row shape for RR aggregates; includes rr/pnl so index-signature trade rows stay assignable. */
export type TradeRrStatsRow = {
  rr?: unknown
  pnl?: unknown
  max_rr_reached?: unknown
}

export function hasStoredRr(value: unknown): value is number {
  if (value === null || value === undefined) return false
  if (typeof value === "string" && value.trim() === "") return false
  const n = Number(value)
  return Number.isFinite(n)
}

/** Blank or invalid input → null; finite numbers including 0 are preserved. */
export function parseOptionalRr(raw: unknown): number | null {
  if (raw === null || raw === undefined) return null
  if (typeof raw === "string" && raw.trim() === "") return null
  const n = Number(raw)
  return Number.isFinite(n) ? n : null
}

/** @deprecated Dashboard Avg R:R uses {@link averageRealizedRrFromTrades}. */
export function averageRrFromTrades(trades: TradeRrStatsRow[]): number | null {
  let sum = 0
  let count = 0

  for (const trade of trades) {
    if (!hasStoredRr(trade.rr)) continue
    sum += Number(trade.rr)
    count += 1
  }

  return count > 0 ? sum / count : null
}

/** Mean max R:R reached over trades with a stored value; null when none qualify. */
export function averageMaxRrReachedFromTrades(
  trades: TradeRrStatsRow[]
): number | null {
  let sum = 0
  let count = 0

  for (const trade of trades) {
    if (!hasStoredRr(trade.max_rr_reached)) continue
    sum += Number(trade.max_rr_reached)
    count += 1
  }

  return count > 0 ? sum / count : null
}

/** Persist max R:R for non-positive P&L; optional finite value when P&L is positive. */
export function maxRrReachedForTradeSave(
  pnl: number,
  parsed: number | null
): number | null | undefined {
  if (!Number.isFinite(pnl)) return parsed ?? undefined
  if (pnl > 0) {
    if (parsed == null) return undefined
    return parsed
  }
  return parsed
}
