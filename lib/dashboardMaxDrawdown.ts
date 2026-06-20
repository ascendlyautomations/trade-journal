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
    runningEquity += Number(trade.pnl) || 0
    if (runningEquity > runningPeak) runningPeak = runningEquity
    const drawdown = runningPeak - runningEquity
    if (drawdown > maxDrawdown) maxDrawdown = drawdown
  }

  return maxDrawdown
}
