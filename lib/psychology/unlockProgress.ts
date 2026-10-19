import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import { checkInsByDate } from "./correlate.ts"
import {
  psychologyTradeDateKey,
  type PsychologyTradeDateFields,
} from "./tradeDateKey.ts"

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
 * Check-ins on Eastern trade dates present in the same filtered trade set.
 * Matches iOS `PsychologyInsightsUnlockProgress.compute`.
 */
export function computePsychologyInsightsUnlockProgress<
  T extends PsychologyTradeDateFields,
>(
  trades: readonly T[],
  checkIns: readonly TraderDailyCheckIn[]
): PsychologyInsightsUnlockProgress {
  const byDate = checkInsByDate(checkIns)
  const tradingDaysWithCheckIn = new Set<string>()
  for (const trade of trades) {
    const key = psychologyTradeDateKey(trade)
    if (key && byDate.has(key)) {
      tradingDaysWithCheckIn.add(key)
    }
  }
  return {
    tradingDayCheckInCount: tradingDaysWithCheckIn.size,
    tradeCount: trades.length,
  }
}
