import type { TraderDailyCheckIn } from "../../dailyCheckIn/types.ts"
import { derivePsychologyGuardrails } from "./comparisons.ts"
import { enrichPsychologyTrades } from "./enrich.ts"
import { analyzePsychologyTrends } from "./trends.ts"
import type {
  PsychologyAnalyticsReport,
  PsychologyCoachFactInsight,
  PsychologyCoachFacts,
  PsychologyInsightCard,
  PsychologyReportTrade,
} from "./types.ts"

function factInsight(card: PsychologyInsightCard): PsychologyCoachFactInsight {
  return {
    id: card.id,
    category: card.category,
    headline: card.headline,
    detail: card.detail,
    sampleSize: card.sampleSize,
    reliability: card.reliability,
  }
}

export function buildPsychologyDataGapMessages(
  report: PsychologyAnalyticsReport,
  trades: readonly PsychologyReportTrade[]
): string[] {
  const gaps: string[] = []
  if (report.baseline.tradeCount < 5) {
    gaps.push("Log at least 5 trades to unlock personalized coaching.")
  }
  if (report.matchedDayCount < 5) {
    gaps.push(
      "Complete daily check-ins on trading days to unlock sleep and mental-state patterns."
    )
  }
  if (trades.filter((trade) => (trade.confidence ?? 0) > 0).length < 5) {
    gaps.push(
      "Add conviction ratings on trades to compare high vs low conviction performance."
    )
  }
  if (trades.filter((trade) => String(trade.emotion ?? "").trim()).length < 5) {
    gaps.push(
      "Tag emotions before entry to see which states correlate with weaker results."
    )
  }
  return gaps
}

function factsFingerprint(facts: Omit<PsychologyCoachFacts, "factsHash">): string {
  return JSON.stringify({
    baseline: facts.baseline,
    topInsights: facts.topInsights.map((row) => row.id),
    trends: facts.trends.map((row) => row.id),
    guardrails: facts.guardrailFacts,
    gaps: facts.dataGaps,
  })
}

export function buildPsychologyCoachFacts(
  report: PsychologyAnalyticsReport,
  trades: readonly PsychologyReportTrade[],
  checkIns: readonly TraderDailyCheckIn[],
  now: Date = new Date(),
  preferences: import("@/lib/analytics/preferenceCompliance.ts").PreferenceRuleContext | null = null
): PsychologyCoachFacts {
  const enriched = enrichPsychologyTrades(trades, checkIns, preferences)
  const trends = analyzePsychologyTrends(trades, checkIns)
  const guardrails = derivePsychologyGuardrails(enriched, preferences)

  const combined = [
    ...report.dashboardCards.filter((card) => card.category === "combined"),
    ...report.sections.flatMap((section) =>
      section.id === "combined"
        ? section.groups.map((row) => ({
            id: row.id,
            category: "combined" as const,
            sectionTitle: section.title,
            headline: row.label,
            detail: section.subtitle ?? "",
            sampleSize: row.metrics.tradeCount,
            reliability: row.metrics.reliability,
            rankingScore: 0,
          }))
        : []
    ),
  ]
  const combinedFacts = [...new Map(combined.map((card) => [card.id, factInsight(card)])).values()]

  const facts: PsychologyCoachFacts = {
    generatedAt: now.getTime(),
    factsHash: "",
    baseline: {
      tradeCount: report.baseline.tradeCount,
      winRate: report.baseline.winRate,
      expectancy: report.baseline.expectancy,
      averagePnL: report.baseline.averagePnL,
      reliability: report.baseline.reliability,
    },
    topInsights: report.dashboardCards.map(factInsight),
    combinedPatterns: combinedFacts,
    trends,
    guardrailFacts: guardrails,
    dataGaps: buildPsychologyDataGapMessages(report, trades),
    hasMinimumData: report.baseline.tradeCount >= 5,
  }
  facts.factsHash = factsFingerprint(facts)
  return facts
}
