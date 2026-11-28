import type { TraderDailyCheckIn } from "../../dailyCheckIn/types.ts"
import { buildTradingRulesComplianceAnalytics } from "@/lib/analytics/tradingRulesComplianceAnalytics.ts"
import {
  complianceTradeFromRow,
  type PreferenceRuleContext,
} from "@/lib/analytics/preferenceCompliance.ts"
import { derivePsychologyGuardrails } from "./comparisons.ts"
import { enrichPsychologyTrades } from "./enrich.ts"
import { analyzePsychologyTrends } from "./trends.ts"
import { buildPsychologyCoachDeterministicSummary } from "./coach.ts"
import { buildMatchedTradingDays } from "../matchedTradingDays.ts"
import { isCompleteCheckIn } from "../../dailyCheckIn/validation.ts"
import type {
  PsychologyAnalyticsReport,
  PsychologyAnalyticsSection,
  PsychologyCoachFactInsight,
  PsychologyCoachFacts,
  PsychologyInsightCard,
  PsychologyReportTrade,
} from "./types.ts"

function factInsight(
  card: PsychologyInsightCard,
  sections: readonly PsychologyAnalyticsSection[]
): PsychologyCoachFactInsight {
  const section = sections.find((row) => row.id === card.id)
  const leader = section?.groups.find((g) => g.highlight) ?? section?.groups[0]
  return {
    id: card.id,
    category: card.category,
    headline: card.headline,
    detail: card.detail,
    sampleSize: card.sampleSize,
    reliability: card.reliability,
    winRate: leader?.metrics.winRate ?? null,
    averagePnL: leader?.metrics.averagePnL ?? null,
    expectancy: leader?.metrics.expectancy ?? null,
  }
}

function comparisonFromSection(
  report: PsychologyAnalyticsReport,
  section: PsychologyAnalyticsReport["sections"][number]
) {
  const card = report.dashboardCards.find((row) => row.id === section.id)
  const left = section.groups[0]
  const right = section.groups[1]
  const mapSide = (row: typeof left | undefined) =>
    row
      ? {
          label: row.label,
          sampleLabel: row.label,
          tradeCount: row.metrics.tradeCount,
          winRate: row.metrics.winRate,
          averagePnL: row.metrics.averagePnL,
          expectancy: row.metrics.expectancy,
          reliability: row.metrics.reliability,
          highlight: row.highlight,
        }
      : {
          label: "",
          sampleLabel: "",
          tradeCount: 0,
          winRate: null,
          averagePnL: null,
          expectancy: null,
          reliability: "insufficient" as const,
          highlight: false,
        }
  return {
    id: section.id,
    category: card?.category ?? section.id,
    title: section.title,
    headline: card?.headline ?? section.title,
    suggestion: card?.detail ?? section.footnote ?? "",
    sampleLine: section.footnote ?? "",
    reliability: left?.metrics.reliability ?? "insufficient",
    favorableSide: left?.highlight ? left.label : (right?.label ?? ""),
    left: mapSide(left),
    right: mapSide(right),
  }
}

function average(values: readonly number[]): number | null {
  if (values.length === 0) return null
  return values.reduce((sum, v) => sum + v, 0) / values.length
}

function buildCheckInAggregates(
  trades: readonly PsychologyReportTrade[],
  checkIns: readonly TraderDailyCheckIn[],
  matchedDayCount: number
) {
  const days = buildMatchedTradingDays(trades, checkIns.filter(isCompleteCheckIn))
  if (days.length === 0) {
    return {
      matchedDayCount,
      averageSleepHours: null,
      averageStress: null,
      averageMood: null,
      averageConfidence: null,
      averageEnergy: null,
      averageFocus: null,
    }
  }
  const sleep = days
    .map((d) => d.checkIn.sleepHours)
    .filter((v): v is number => v != null)
  const stress = days
    .map((d) => d.checkIn.stressLevel)
    .filter((v): v is number => v != null)
  const mood = days
    .map((d) => d.checkIn.morningRating)
    .filter((v): v is number => v != null)
  const sleepQuality = days
    .map((d) => d.checkIn.sleepQuality)
    .filter((v): v is number => v != null)
  const energy = days
    .map((d) => d.checkIn.energyLevel)
    .filter((v): v is number => v != null)
  const focus = days
    .map((d) => d.checkIn.focusLevel)
    .filter((v): v is number => v != null)

  return {
    matchedDayCount,
    averageSleepHours: average(sleep),
    averageStress: average(stress),
    averageMood: average(mood),
    averageConfidence: average(sleepQuality),
    averageEnergy: average(energy),
    averageFocus: average(focus),
  }
}

function buildTradingRulesFacts(
  trades: readonly PsychologyReportTrade[],
  preferences: PreferenceRuleContext | null
): PsychologyCoachFacts["tradingRulesCompliance"] {
  if (!preferences) return null
  const complianceTrades = trades
    .map((trade) =>
      complianceTradeFromRow({
        entry_time: trade.entry_time,
        created_at: trade.created_at ?? trade.entry_time,
        pnl: trade.pnl,
        account_id: trade.accountId ?? null,
        ticker: null,
        symbol: null,
      })
    )
    .filter((row): row is NonNullable<typeof row> => row != null)
  const result = buildTradingRulesComplianceAnalytics(complianceTrades, preferences)
  const topViolationRules = result.impacts
    .filter((row) => row.sufficientSample)
    .sort((a, b) => b.violated.priced - a.violated.priced)
    .slice(0, 5)
    .map((row) => ({
      ruleId: row.ruleId,
      ruleLabel: row.ruleLabel,
      violationCount: row.violated.priced,
      followedWinRate: row.winRateFollowed,
      violatedWinRate: row.winRateViolated,
    }))

  return {
    adherencePercent: result.score.adherencePercent,
    evaluated: result.score.evaluated,
    followed: result.score.followed,
    violated: result.score.violated,
    topViolationRules,
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
    scope: facts.scope,
    baseline: facts.baseline,
    comparisons: facts.comparisons?.map((row) => row.id),
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
  preferences: PreferenceRuleContext | null = null,
  scope?: { label: string; fingerprint: string }
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
  const combinedFacts = [
    ...new Map(
      combined.map((card) => [card.id, factInsight(card, report.sections)])
    ).values(),
  ]

  const facts: PsychologyCoachFacts = {
    generatedAt: now.getTime(),
    factsHash: "",
    scope: scope ?? { label: "All accounts", fingerprint: "default" },
    reportMeta: {
      enrichedTradeCount: report.enrichedTradeCount,
      checkInMatchedTradeCount: report.checkInMatchedTradeCount,
      matchedDayCount: report.matchedDayCount,
    },
    baseline: {
      tradeCount: report.baseline.tradeCount,
      winRate: report.baseline.winRate,
      expectancy: report.baseline.expectancy,
      averagePnL: report.baseline.averagePnL,
      reliability: report.baseline.reliability,
    },
    comparisons: report.sections.map((section) =>
      comparisonFromSection(report, section)
    ),
    topInsights: report.dashboardCards.map((card) =>
      factInsight(card, report.sections)
    ),
    combinedPatterns: combinedFacts,
    trends,
    checkInAggregates: buildCheckInAggregates(
      trades,
      checkIns,
      report.matchedDayCount
    ),
    tradingRulesCompliance: buildTradingRulesFacts(trades, preferences),
    deterministicCoach: {
      overview: "",
      doingWell: [],
      watchItems: [],
      recommendations: [],
    },
    guardrailFacts: guardrails,
    dataGaps: buildPsychologyDataGapMessages(report, trades),
    hasMinimumData: report.baseline.tradeCount >= 5,
  }
  const deterministic = buildPsychologyCoachDeterministicSummary(facts)
  facts.deterministicCoach = {
    overview: deterministic.overview,
    doingWell: deterministic.doingWell,
    watchItems: deterministic.watchItems,
    recommendations: deterministic.recommendations,
  }
  facts.factsHash = factsFingerprint(facts)
  return facts
}