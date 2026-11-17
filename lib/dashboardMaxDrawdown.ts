import { knownPnl } from "./analytics/knownPnl"
import {
  compareDashboardTradesChronological,
  type DashboardTradeDateFields,
} from "./dashboardTradeDate"

/**
 * Max peak-to-trough drop on chronological cumulative P&L.
 * runningPeak tracks the high-water mark; maxDrawdown = max(runningPeak − runningEquity).
 */
export function computeMaxDrawdown(
  trades: (DashboardTradeDateFields & { pnl?: unknown })[]
): number {
  const chronological = [...trades].sort(compareDashboardTradesChronological)

  let runningEquity = 0
  let runningPeak = 0
  let maxDrawdown = 0

  for (const trade of chronological) {
    const pnl = knownPnl(trade.pnl)
    if (pnl == null) continue
    runningEquity += pnl
    if (runningEquity > runningPeak) runningPeak = runningEquity
    const drawdown = runningPeak - runningEquity
    if (drawdown > maxDrawdown) maxDrawdown = drawdown
  }

  return maxDrawdown
}
