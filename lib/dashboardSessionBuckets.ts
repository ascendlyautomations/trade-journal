import {
  TRADING_SESSION_DISPLAY_ORDER,
  normalizeTradingSessionLabel,
  tradingSessionDisplayName,
  type TradingSessionLabel,
} from "./tradingSession.ts"

export type DashboardSessionBucket = TradingSessionLabel

export const DASHBOARD_SESSION_DISPLAY_ORDER: readonly DashboardSessionBucket[] =
  TRADING_SESSION_DISPLAY_ORDER

export const DASHBOARD_SESSION_COLORS: Record<DashboardSessionBucket, string> =
  {
    "NY AM": "#34d399",
    "NY Lunch": "#10b981",
    "NY PM": "#059669",
    London: "#60a5fa",
    Asia: "#c084fc",
    After: "#94a3b8",
  }

/** Map stored session text to dashboard analytics buckets. */
export function normalizeSessionBucket(
  sessionRaw: string | null | undefined
): DashboardSessionBucket | null {
  return normalizeTradingSessionLabel(sessionRaw)
}

export function dashboardSessionDisplayName(name: DashboardSessionBucket): string {
  return tradingSessionDisplayName(name)
}

export type SessionBucketTotals = {
  totalTrades: number
  wins: number
  totalPnL: number
}

/** Zeroed session rows for every canonical bucket (marketing + dashboard local analytics). */
export function createEmptySessionBuckets(): Record<
  DashboardSessionBucket,
  SessionBucketTotals
> {
  return Object.fromEntries(
    DASHBOARD_SESSION_DISPLAY_ORDER.map((name) => [
      name,
      { totalTrades: 0, wins: 0, totalPnL: 0 },
    ])
  ) as Record<DashboardSessionBucket, SessionBucketTotals>
}

/** Defensive increment — no-ops if the bucket key is missing from the record. */
export function applyTradeToSessionBucket(
  buckets: Record<DashboardSessionBucket, SessionBucketTotals>,
  bucket: DashboardSessionBucket,
  pnl: number
): void {
  const row = buckets[bucket]
  if (!row) return
  row.totalTrades += 1
  row.totalPnL += pnl
  if (pnl > 0) row.wins += 1
}
