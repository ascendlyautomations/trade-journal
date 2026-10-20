import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import { countPsychologyCheckInHistoryDays } from "./checkInHistory.ts"
import type { PsychologyTradeDateFields } from "./tradeDateKey.ts"

/** Port of iOS `PsychologyInsightsUnlockProgress`. */
export const PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT = 5

export type PsychologyInsightsUnlockProgress = {
  tradingDayCheckInCount: number
  tradeCount: number
}

export const EMPTY_PSYCHOLOGY_UNLOCK: PsychologyInsightsUnlockProgress = {
  tradingDayCheckInCount: 0,
  tradeCount: 0,
}

export function showsPsychologyInsightsRequirement(
  progress: PsychologyInsightsUnlockProgress
): boolean {
  return (
    progress.tradingDayCheckInCount < PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT ||
    progress.tradeCount < PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT
  )
}

export function displayTradeCountForGate(
  progress: PsychologyInsightsUnlockProgress
): number {
  return Math.min(progress.tradeCount, PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT)
}

export function displayCheckInDayCountForGate(
  progress: PsychologyInsightsUnlockProgress
): number {
  return Math.min(
    progress.tradingDayCheckInCount,
    PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT
  )
}

/**
 * Check-in days: same count as Check-In History → Psychology filter.
 * Trades: current filtered dashboard trade count.
 */
export function computePsychologyInsightsUnlockProgress<
  T extends PsychologyTradeDateFields,
>(
  trades: readonly T[],
  checkIns: readonly TraderDailyCheckIn[]
): PsychologyInsightsUnlockProgress {
  return {
    tradingDayCheckInCount: countPsychologyCheckInHistoryDays(checkIns),
    tradeCount: trades.length,
  }
}
