import { hasStoredRr } from "./tradeRr.ts"

/** Rolling 7-day window aligned with dashboard "This Week" filter. */
export function getFeaturedWeekStartIso(now = new Date()): string {
  const start = new Date(now)
  start.setUTCDate(start.getUTCDate() - 7)
  return start.toISOString()
}

export function isPublicDiscoverableTradeRow(row: {
  trades?: { is_public?: boolean | null } | { is_public?: boolean | null }[] | null
  profiles?: { is_private?: boolean | null } | { is_private?: boolean | null }[] | null
}): boolean {
  const trade = row.trades
  const tradeRow = trade ? (Array.isArray(trade) ? trade[0] : trade) : null
  if (tradeRow?.is_public !== true) return false

  const profile = row.profiles
  const profileRow = profile ? (Array.isArray(profile) ? profile[0] : profile) : null
  return profileRow?.is_private !== true
}

export function pickBestPnlPost<T extends { pnl?: unknown; created_at?: string }>(
  rows: readonly T[]
): T | null {
  let best: T | null = null

  for (const row of rows) {
    const pnl = Number(row.pnl)
    if (!Number.isFinite(pnl)) continue
    if (!best) {
      best = row
      continue
    }

    const bestPnl = Number(best.pnl)
    if (pnl > bestPnl) {
      best = row
      continue
    }
    if (pnl < bestPnl) continue

    const rowAt = String(row.created_at ?? "")
    const bestAt = String(best.created_at ?? "")
    if (rowAt > bestAt) best = row
  }

  return best
}

export function pickHighestRrPost<T extends { rr?: unknown; created_at?: string }>(
  rows: readonly T[]
): T | null {
  let best: T | null = null

  for (const row of rows) {
    if (!hasStoredRr(row.rr)) continue
    const rr = Number(row.rr)
    if (!best) {
      best = row
      continue
    }

    const bestRr = Number(best.rr)
    if (rr > bestRr) {
      best = row
      continue
    }
    if (rr < bestRr) continue

    const rowAt = String(row.created_at ?? "")
    const bestAt = String(best.created_at ?? "")
    if (rowAt > bestAt) best = row
  }

  return best
}
