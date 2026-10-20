import type { EquityChartPoint } from "@/app/components/dashboard/DashboardEquityCurve"
import {
  compareDashboardTradesChronological,
  resolveDashboardTradeTimeSource,
} from "@/lib/dashboardTradeDate"
import { buildEquityCurveFromTrades } from "@/lib/performanceShare"

/** Map cumulative P&L steps to dashboard equity chart points (chronological). */
export function buildBacktestLabEquityChartData(
  trades: readonly Record<string, unknown>[]
): EquityChartPoint[] {
  const chronological = [...trades].sort(compareDashboardTradesChronological)
  if (!chronological.length) return []

  const steps = buildEquityCurveFromTrades(chronological)
  return steps.map((point, index) => {
    if (index === 0) {
      const anchor =
        resolveDashboardTradeTimeSource(chronological[0]) ??
        chronological[0].created_at ??
        new Date(0).toISOString()
      return { date: String(anchor), equity: point.equity }
    }
    const trade = chronological[index - 1]
    const date =
      resolveDashboardTradeTimeSource(trade) ??
      trade.created_at ??
      String(index)
    return { date: String(date), equity: point.equity }
  })
}
