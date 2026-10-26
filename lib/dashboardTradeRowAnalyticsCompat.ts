import type { DashboardTradeRow } from "@/app/components/dashboard/dashboardTypes"
import { computeHoldTimeStats } from "@/lib/dashboardHoldTimeStats"
import { computeLongShortPerformance } from "@/lib/dashboardLongShortStats"
import { computeMaxDrawdown } from "@/lib/dashboardMaxDrawdown"
import { computeDashboardRrTargetAnalysis } from "@/lib/dashboardRrTargetAnalysis"
import {
  averageMaxRrReachedFromTrades,
  averageRrFromTrades,
} from "@/lib/tradeRr"
import {
  averageRealizedRrFromTrades,
  resolveRealizedRr,
} from "@/lib/tradePointsAndRealizedRr"

/**
 * Compile-time guard: `DashboardTradeRow` must stay assignable to dashboard RR analytics.
 * Vercel runs `next build` TypeScript on the whole project; breaking this function fails CI.
 */
export function typecheckDashboardTradeRowAnalyticsCompat(
  rows: DashboardTradeRow[]
): void {
  void averageRrFromTrades(rows)
  void averageMaxRrReachedFromTrades(rows)
  void averageRealizedRrFromTrades(rows)
  void computeDashboardRrTargetAnalysis(rows)
  void computeHoldTimeStats(rows)
  void computeMaxDrawdown(rows)
  void computeLongShortPerformance(rows)
  if (rows[0]) void resolveRealizedRr(rows[0])
}
