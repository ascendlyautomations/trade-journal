import { isCompleteCheckIn } from "../dailyCheckIn/validation.ts"
import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import { psychologyTradeDateKey } from "../psychology/tradeDateKey.ts"
import { resolveScorecardReliability } from "./reliability.ts"
import type { ScorecardCategoryResult, ScorecardTrade } from "./types.ts"
import { SCORECARD_CATEGORY_WEIGHTS } from "./types.ts"

export function countEasternCalendarTradingDays(trades: readonly ScorecardTrade[]): number {
  const keys = new Set<string>()
  for (const trade of trades) {
    const key =
      trade.psychologyDayKey ??
      psychologyTradeDateKey({
        entry_time: new Date(trade.entryTimeMs).toISOString(),
        created_at: new Date(trade.entryTimeMs).toISOString(),
      })
    if (key) keys.add(key)
  }
  return keys.size
}

/**
 * Psychology is not scored on the scorecard. Check-in coverage is a readout.
 * Emotion stays on the trade so other psychology features can use the same row.
 */
export function scorePsychologyCategory(
  trades: readonly ScorecardTrade[],
  checkIns: readonly TraderDailyCheckIn[],
  _dashboardTradingDayCount: number
): ScorecardCategoryResult {
  const easternTradingDays = countEasternCalendarTradingDays(trades)
  const completeDates = new Set(
    checkIns.filter(isCompleteCheckIn).map((checkIn) => checkIn.checkInDate)
  )
  let matchedDayCount = 0
  const seen = new Set<string>()
  for (const trade of trades) {
    const key =
      trade.psychologyDayKey ??
      psychologyTradeDateKey({
        entry_time: new Date(trade.entryTimeMs).toISOString(),
        created_at: new Date(trade.entryTimeMs).toISOString(),
      })
    if (!key || seen.has(key)) continue
    seen.add(key)
    if (completeDates.has(key)) matchedDayCount += 1
  }

  const coveragePercent =
    easternTradingDays > 0 ? Math.round((matchedDayCount / easternTradingDays) * 100) : 0

  return {
    id: "psychology",
    title: "Psychology",
    weight: SCORECARD_CATEGORY_WEIGHTS.psychology,
    score: null,
    coveragePercent,
    reliability: resolveScorecardReliability(matchedDayCount),
    eligible: false,
    subMetrics: [
      {
        id: "psych.checkin_coverage",
        label: "Check-ins on trading days",
        value:
          easternTradingDays > 0
            ? `${matchedDayCount} of ${easternTradingDays} trading days`
            : "No trading days in this scope",
        explanation: "Eastern calendar days with a complete check-in and at least one trade.",
        sampleSize: easternTradingDays,
        sampleLabel: "trading days",
      },
    ],
    strengths: [],
    weaknesses: [],
    dataGaps: [],
  }
}
