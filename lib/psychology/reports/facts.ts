import type { TraderDailyCheckIn } from "../../dailyCheckIn/types.ts"
import { enrichPsychologyTrades, resolveSequenceBucket } from "./enrich.ts"
import { psychologyTradeMetrics, qualifiesForComparison, qualifiesForDashboardCard } from "./metrics.ts"
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

function dataGaps(
  report: PsychologyAnalyticsReport,
  trades: readonly PsychologyReportTrade[]
): string[] {
  const gaps: string[] = []
  if (report.baseline.tradeCount < 5) {
    gaps.push("Log at least 5 trades to unlock personalized coaching.")
  }
  if (report.checkInMatchedTradeCount < 5) {
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
  now: Date = new Date()
): PsychologyCoachFacts {
  const enriched = enrichPsychologyTrades(trades, checkIns)
  const trends = analyzePsychologyTrends(trades, checkIns)
  const afterTwo = enriched.filter((row) => row.consecutiveLossesBefore >= 2)
  const afterTwoMetrics = psychologyTradeMetrics(afterTwo.map((row) => row.trade))

  let lowSleepHoursThreshold: number | null = null
  let lowSleepExpectancy: number | null = null
  const lowSleep = enriched.filter((row) => {
    const hours = row.dailyCheckIn?.sleepHours
    return hours != null && hours < 6
  })
  if (lowSleep.length >= 10) {
    const metrics = psychologyTradeMetrics(lowSleep.map((row) => row.trade))
    if (qualifiesForComparison(metrics.reliability)) {
      lowSleepHoursThreshold = 6
      lowSleepExpectancy = metrics.expectancy ?? metrics.averagePnL
    }
  }

  let maxTradesDaySoftLimit: number | null = null
  let lateTradeAveragePnL: number | null = null
  let earlyTradeAveragePnL: number | null = null
  const grouped = new Map<string, typeof enriched>()
  for (const item of enriched) {
    const bucket = resolveSequenceBucket(item.tradeNumberInDay)
    const list = grouped.get(bucket) ?? []
    list.push(item)
    grouped.set(bucket, list)
  }
  const early = [
    ...(grouped.get("Trade #1") ?? []),
    ...(grouped.get("Trade #2") ?? []),
    ...(grouped.get("Trade #3") ?? []),
  ]
  const late = grouped.get("Trade #5+") ?? []
  if (early.length >= 5 && late.length >= 5) {
    const earlyM = psychologyTradeMetrics(early.map((row) => row.trade))
    const lateM = psychologyTradeMetrics(late.map((row) => row.trade))
    if (
      qualifiesForDashboardCard(earlyM.reliability) &&
      qualifiesForDashboardCard(lateM.reliability) &&
      (earlyM.averagePnL ?? 0) > (lateM.averagePnL ?? 0) + 5
    ) {
      maxTradesDaySoftLimit = 4
      earlyTradeAveragePnL = earlyM.averagePnL
      lateTradeAveragePnL = lateM.averagePnL
    }
  }

  const checkpoint =
    afterTwo.length >= 10 &&
    qualifiesForComparison(afterTwoMetrics.reliability) &&
    (afterTwoMetrics.winRate ?? 0) < (report.baseline.winRate ?? 0) - 0.05
      ? 2
      : null

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
    guardrailFacts: {
      consecutiveLossCheckpoint: checkpoint,
      consecutiveLossWinRateAfter: afterTwoMetrics.winRate,
      consecutiveLossBaselineWinRate: report.baseline.winRate,
      lowSleepHoursThreshold,
      lowSleepExpectancy,
      maxTradesDaySoftLimit,
      lateTradeAveragePnL,
      earlyTradeAveragePnL,
    },
    dataGaps: dataGaps(report, trades),
    hasMinimumData: report.baseline.tradeCount >= 5,
  }
  facts.factsHash = factsFingerprint(facts)
  return facts
}
