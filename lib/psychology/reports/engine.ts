import type { TraderDailyCheckIn } from "../../dailyCheckIn/types.ts"
import {
  buildInterpretivePsychologyInsights,
  buildPsychologyAdvancedSections,
  countMatchedPsychologyDays,
} from "./comparisons.ts"
import { enrichPsychologyTrades } from "./enrich.ts"
import { psychologyTradeMetrics } from "./metrics.ts"
import type { PsychologyAnalyticsReport, PsychologyReportTrade } from "./types.ts"
import type { PreferenceRuleContext } from "@/lib/analytics/preferenceCompliance.ts"

export function buildPsychologyAnalyticsReport(
  trades: readonly PsychologyReportTrade[],
  checkIns: readonly TraderDailyCheckIn[],
  now: Date = new Date(),
  preferences: PreferenceRuleContext | null = null
): PsychologyAnalyticsReport {
  const enriched = enrichPsychologyTrades(trades, checkIns, preferences)
  const baseline = psychologyTradeMetrics(enriched.map((row) => row.trade))
  return {
    generatedAt: now.getTime(),
    baseline,
    dashboardCards: buildInterpretivePsychologyInsights(enriched, preferences),
    sections: buildPsychologyAdvancedSections(enriched, preferences),
    enrichedTradeCount: enriched.length,
    checkInMatchedTradeCount: enriched.filter((row) => row.dailyCheckIn != null).length,
    matchedDayCount: countMatchedPsychologyDays(trades, checkIns),
  }
}
