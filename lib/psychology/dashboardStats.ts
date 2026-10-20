import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import { buildCheckInSummary, type PsychologyCheckInSummary } from "./checkInSummary.ts"
import { isCompleteCheckIn } from "../dailyCheckIn/validation.ts"
import { checkInsMatchingTrades } from "./correlate.ts"
import type { PsychologyTradeDateFields } from "./tradeDateKey.ts"
import {
  computePsychologyInsightsUnlockProgress,
  showsPsychologyInsightsRequirement,
  type PsychologyInsightsUnlockProgress,
} from "./unlockProgress.ts"

export type DashboardPsychologyStats = {
  unlock: PsychologyInsightsUnlockProgress
  summary: PsychologyCheckInSummary
  showMetrics: boolean
}

/**
 * Filter-aware dashboard stats: unlock and averages both use check-ins
 * whose Eastern date appears on the current filtered trade set.
 */
export function buildDashboardPsychologyStats<
  T extends PsychologyTradeDateFields,
>(
  trades: readonly T[],
  checkIns: readonly TraderDailyCheckIn[]
): DashboardPsychologyStats {
  const unlock = computePsychologyInsightsUnlockProgress(trades, checkIns)
  const matched = checkInsMatchingTrades(
    trades,
    checkIns.filter(isCompleteCheckIn)
  )
  const showMetrics = !showsPsychologyInsightsRequirement(unlock)
  return {
    unlock,
    summary: showMetrics
      ? buildCheckInSummary(matched)
      : buildCheckInSummary([]),
    showMetrics,
  }
}
