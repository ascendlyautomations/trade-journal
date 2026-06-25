/** RR storage and analytics helpers — missing RR is null, not 0. */

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

/** Mean RR over trades with a stored RR value; null when none qualify. */
export function averageRrFromTrades(
  trades: { rr?: unknown }[]
): number | null {
  let sum = 0
  let count = 0

  for (const trade of trades) {
    if (!hasStoredRr(trade.rr)) continue
    sum += Number(trade.rr)
    count += 1
  }

  return count > 0 ? sum / count : null
}
