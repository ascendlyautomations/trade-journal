import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import { buildPsychologyDataGapMessages } from "./reports/facts.ts"
import type {
  PsychologyAnalyticsReport,
  PsychologyReportTrade,
} from "./reports/types.ts"
import {
  computePsychologyInsightsUnlockProgress,
  type PsychologyInsightsUnlockProgress,
} from "./unlockProgress.ts"

export const PSYCHOLOGY_UNLOCK_OVERVIEW_COPY =
  "5 check-in days and 5 trades unlock your analytics overview. Personalized comparison insights need more matched data and tagged trades."

export function buildPsychologyComparisonInsightGapMessage(
  report: PsychologyAnalyticsReport
): string | null {
  if (report.dashboardCards.length > 0) return null
  return "Comparison insights need at least 5 trades in each group we compare (often 10+ total with check-ins and psychology tags on the same days)."
}

/** Actionable messages after the 5/5 gate — never a generic empty state. */
export function buildPostUnlockInsightGapMessages(
  report: PsychologyAnalyticsReport,
  trades: readonly PsychologyReportTrade[]
): string[] {
  const messages = [...buildPsychologyDataGapMessages(report, trades)]
  const comparison = buildPsychologyComparisonInsightGapMessage(report)
  if (comparison) messages.push(comparison)
  return messages
}

export type PsychologyAnalyticsOverviewCounts = {
  unlock: PsychologyInsightsUnlockProgress
  checkInPsychDays: number
  scopedTradeCount: number
  matchedTradeCount: number
}

export function psychologyAnalyticsOverviewCounts(
  report: PsychologyAnalyticsReport,
  trades: readonly PsychologyReportTrade[],
  checkIns: readonly TraderDailyCheckIn[]
): PsychologyAnalyticsOverviewCounts {
  const unlock = computePsychologyInsightsUnlockProgress(trades, checkIns)
  return {
    unlock,
    checkInPsychDays: unlock.tradingDayCheckInCount,
    scopedTradeCount: report.baseline.tradeCount,
    matchedTradeCount: report.checkInMatchedTradeCount,
  }
}
