import type { TraderDailyCheckIn } from "../../dailyCheckIn/types.ts"
import { psychologyTradeDateKey } from "../tradeDateKey.ts"
import { buildCheckInSummary } from "../checkInSummary.ts"
import {
  psychologyReportID,
  psychologyReportTitle,
} from "./catalog.ts"
import { buildPsychologyCoachSummary, buildPsychologyRecommendations } from "./coach.ts"
import { enrichPsychologyTrades, resolveSequenceBucket } from "./enrich.ts"
import { buildPsychologyAnalyticsReport } from "./engine.ts"
import { buildPsychologyCoachFacts } from "./facts.ts"
import {
  formatPsychologyHours,
  formatPsychologyInteger,
  formatPsychologyMoney,
  formatPsychologyPercent,
  formatPsychologyRating,
  formatPsychologyRatio,
  formatPsychologyStressAverage,
  formatPsychologyWinRate,
} from "./format.ts"
import { psychologyTradeMetrics } from "./metrics.ts"
import {
  filterTradesForPeriod,
  psychologyPeriodBounds,
} from "./periods.ts"
import type {
  PsychologyReport,
  PsychologyReportBehaviorSummary,
  PsychologyReportComparison,
  PsychologyReportMetricRow,
  PsychologyReportPeriodRef,
  PsychologyReportSection,
  PsychologyReportTemplate,
  PsychologyReportTrade,
  PsychologyReportTradingPsychology,
} from "./types.ts"

function filterCheckIns(
  checkIns: readonly TraderDailyCheckIn[],
  startKey: string,
  endKey: string
): TraderDailyCheckIn[] {
  return checkIns.filter(
    (row) => row.checkInDate >= startKey && row.checkInDate <= endKey
  )
}

function buildTradingPsychology(
  trades: readonly PsychologyReportTrade[]
): PsychologyReportTradingPsychology {
  const taggedPlan = trades.filter((trade) => trade.followedPlan != null)
  const convictions = trades
    .map((trade) => trade.confidence)
    .filter((value): value is number => value != null && value > 0)
  const emotions = trades
    .map((trade) => String(trade.emotion ?? "").trim())
    .filter(Boolean)
  const emotionCounts = new Map<string, number>()
  for (const emotion of emotions) {
    emotionCounts.set(emotion, (emotionCounts.get(emotion) ?? 0) + 1)
  }
  let mostCommonEmotion: string | null = null
  let mostCount = 0
  for (const [emotion, count] of emotionCounts) {
    if (count > mostCount) {
      mostCommonEmotion = emotion
      mostCount = count
    }
  }
  const execRatings = trades
    .map((trade) => trade.executionRating)
    .filter((value): value is number => value != null && value > 0)

  return {
    followedPlanRate: taggedPlan.length
      ? taggedPlan.filter((trade) => trade.followedPlan === true).length /
        taggedPlan.length
      : null,
    averageConviction: convictions.length
      ? convictions.reduce((sum, value) => sum + value, 0) / convictions.length
      : null,
    mostCommonEmotion,
    fomoTradeCount: emotions.filter(
      (emotion) => emotion.toLowerCase() === "fomo"
    ).length,
    frustratedTradeCount: emotions.filter(
      (emotion) => emotion.toLowerCase() === "frustrated"
    ).length,
    averageExecutionRating: execRatings.length
      ? execRatings.reduce((sum, value) => sum + value, 0) / execRatings.length
      : null,
  }
}

function buildBehavior(
  periodTrades: readonly PsychologyReportTrade[],
  checkIns: readonly TraderDailyCheckIn[],
  baselineWinRate: number | null
): PsychologyReportBehaviorSummary {
  const enriched = enrichPsychologyTrades(periodTrades, checkIns)
  const dayCounts = new Map<string, number>()
  for (const item of enriched) {
    const key = psychologyTradeDateKey(item.trade)
    if (!key) continue
    dayCounts.set(key, (dayCounts.get(key) ?? 0) + 1)
  }
  const afterTwo = enriched.filter((row) => row.consecutiveLossesBefore >= 2)
  const afterTwoMetrics = psychologyTradeMetrics(afterTwo.map((row) => row.trade))
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
  const earlyM = psychologyTradeMetrics(early.map((row) => row.trade))
  const lateM = psychologyTradeMetrics(late.map((row) => row.trade))

  return {
    averageTradesPerDay: dayCounts.size
      ? [...dayCounts.values()].reduce((sum, value) => sum + value, 0) / dayCounts.size
      : null,
    afterTwoLossesWinRate: afterTwo.length ? afterTwoMetrics.winRate : null,
    afterTwoLossesBaselineWinRate: afterTwo.length ? baselineWinRate : null,
    earlyTradeAvgPnL: early.length ? earlyM.averagePnL : null,
    lateTradeAvgPnL: late.length ? lateM.averagePnL : null,
  }
}

function planRate(trades: readonly PsychologyReportTrade[]): number | null {
  const tagged = trades.filter((trade) => trade.followedPlan != null)
  if (!tagged.length) return null
  return tagged.filter((trade) => trade.followedPlan === true).length / tagged.length
}

function avgSleep(checkIns: readonly TraderDailyCheckIn[]): number | null {
  const hours = checkIns
    .map((row) => row.sleepHours)
    .filter((value): value is number => value != null)
  if (!hours.length) return null
  return hours.reduce((sum, value) => sum + value, 0) / hours.length
}

function avgRating(values: number[]): number | null {
  if (!values.length) return null
  return values.reduce((sum, value) => sum + value, 0) / values.length
}

function buildComparisons(
  periodRef: PsychologyReportPeriodRef,
  trades: readonly PsychologyReportTrade[],
  checkIns: readonly TraderDailyCheckIn[],
  now: Date
): PsychologyReportComparison[] {
  if (periodRef.template !== "monthly") return []
  const bounds = psychologyPeriodBounds(periodRef, now)
  const [year, month] = bounds.startDateKey.slice(0, 7).split("-").map(Number)
  const prevMonth = month === 1 ? 12 : month - 1
  const prevYear = month === 1 ? year - 1 : year
  const prevBoundsEnd = new Date(bounds.startMs - 1)
  const priorBounds = psychologyPeriodBounds(
    {
      template: "monthly",
      periodID: `month:${prevYear}-${String(prevMonth).padStart(2, "0")}`,
    },
    prevBoundsEnd
  )
  const currentTrades = filterTradesForPeriod(trades, bounds)
  const priorTrades = filterTradesForPeriod(trades, priorBounds)
  if (currentTrades.length < 10 || priorTrades.length < 10) return []

  const currentCheckIns = filterCheckIns(checkIns, bounds.startDateKey, bounds.endDateKey)
  const priorCheckIns = filterCheckIns(
    checkIns,
    priorBounds.startDateKey,
    priorBounds.endDateKey
  )

  const comparisons: PsychologyReportComparison[] = []
  const curPlan = planRate(currentTrades)
  const prevPlan = planRate(priorTrades)
  if (curPlan != null && prevPlan != null && Math.abs(curPlan - prevPlan) >= 0.08) {
    comparisons.push({
      headline: curPlan > prevPlan ? "Plan adherence improved" : "Plan adherence slipped",
      detail: `This month: ${formatPsychologyPercent(curPlan * 100)} vs prior month: ${formatPsychologyPercent(prevPlan * 100)}`,
      reliability: "developing",
    })
  }

  const curSleep = avgSleep(currentCheckIns)
  const prevSleep = avgSleep(priorCheckIns)
  if (
    curSleep != null &&
    prevSleep != null &&
    Math.abs(curSleep - prevSleep) >= 0.5 &&
    currentCheckIns.length >= 5 &&
    priorCheckIns.length >= 5
  ) {
    comparisons.push({
      headline: curSleep > prevSleep ? "Average sleep increased" : "Average sleep decreased",
      detail: `This month: ${formatPsychologyHours(curSleep)} vs prior: ${formatPsychologyHours(prevSleep)}`,
      reliability: "developing",
    })
  }

  const curFocus = avgRating(
    currentCheckIns
      .map((row) => row.focusLevel)
      .filter((value): value is number => value != null)
  )
  const prevFocus = avgRating(
    priorCheckIns
      .map((row) => row.focusLevel)
      .filter((value): value is number => value != null)
  )
  if (
    curFocus != null &&
    prevFocus != null &&
    Math.abs(curFocus - prevFocus) >= 0.4 &&
    currentCheckIns.length >= 5
  ) {
    comparisons.push({
      headline: curFocus > prevFocus ? "Focus ratings improved" : "Focus ratings declined",
      detail: `This month avg: ${formatPsychologyRating(curFocus)} vs prior: ${formatPsychologyRating(prevFocus)}`,
      reliability: "developing",
    })
  }

  return comparisons
}

function performanceSection(baseline: ReturnType<typeof psychologyTradeMetrics>): PsychologyReportSection {
  return {
    id: "performance",
    title: "Performance Overview",
    subtitle: `${formatPsychologyInteger(baseline.tradeCount)} trades in period`,
    bullets: [],
    metrics: [
      { label: "P&L", value: formatPsychologyMoney(baseline.totalPnL) },
      { label: "Win Rate", value: formatPsychologyWinRate(baseline.winRate) },
      { label: "Expectancy", value: formatPsychologyMoney(baseline.expectancy ?? 0) },
      { label: "Avg Trade", value: formatPsychologyMoney(baseline.averagePnL ?? 0) },
      { label: "Profit Factor", value: formatPsychologyRatio(baseline.profitFactor) },
    ],
  }
}

function checkInSection(
  summary: ReturnType<typeof buildCheckInSummary>
): PsychologyReportSection {
  const metrics: PsychologyReportMetricRow[] = [
    { label: "Check-ins", value: formatPsychologyInteger(summary.checkInCount) },
  ]
  if (summary.averageSleepHours != null) {
    metrics.push({ label: "Avg Sleep", value: formatPsychologyHours(summary.averageSleepHours) })
  }
  if (summary.averageFocus != null) {
    metrics.push({ label: "Avg Focus", value: formatPsychologyRating(summary.averageFocus) })
  }
  if (summary.averageStress != null) {
    metrics.push({
      label: "Avg Stress",
      value: formatPsychologyStressAverage(summary.averageStress),
    })
  }
  return {
    id: "checkIn",
    title: "Daily Check-In Trends",
    subtitle: null,
    bullets: [],
    metrics,
  }
}

function filterSectionsForTemplate(
  sections: PsychologyReportSection[],
  template: PsychologyReportTemplate
): PsychologyReportSection[] {
  switch (template) {
    case "weekly":
    case "monthly":
      return sections
    case "sleepPerformance":
      return sections.filter((section) =>
        ["performance", "sleep", "checkIn", "trends"].includes(section.id)
      )
    case "discipline":
      return sections.filter((section) =>
        ["performance", "discipline", "recommendations"].includes(section.id)
      )
    case "emotions":
      return sections.filter((section) =>
        ["performance", "emotion", "recommendations"].includes(section.id)
      )
    case "afterLosses":
      return sections.filter((section) =>
        ["performance", "afterLosses", "recommendations"].includes(section.id)
      )
    case "mentalState":
      return sections.filter((section) =>
        ["performance", "checkIn", "mentalState"].includes(section.id)
      )
    case "tradeFrequency":
      return sections.filter((section) =>
        ["performance", "tradeFrequency", "recommendations"].includes(section.id)
      )
  }
}

export function generatePsychologyReport(
  periodRef: PsychologyReportPeriodRef,
  trades: readonly PsychologyReportTrade[],
  checkIns: readonly TraderDailyCheckIn[],
  now: Date = new Date()
): PsychologyReport {
  const bounds = psychologyPeriodBounds(periodRef, now)
  const periodTrades = filterTradesForPeriod(trades, bounds)
  const periodCheckIns = filterCheckIns(
    checkIns,
    bounds.startDateKey,
    bounds.endDateKey
  )
  const analytics = buildPsychologyAnalyticsReport(periodTrades, periodCheckIns, now)
  const facts = buildPsychologyCoachFacts(analytics, periodTrades, periodCheckIns, now)
  const summary = buildPsychologyCoachSummary(facts)
  const checkInSummary = buildCheckInSummary(periodCheckIns)
  const tradingPsych = buildTradingPsychology(periodTrades)
  const behavior = buildBehavior(periodTrades, periodCheckIns, analytics.baseline.winRate)
  const comparisons = [
    ...buildComparisons(periodRef, trades, checkIns, now),
    ...facts.trends.slice(0, 2).map((trend) => ({
      headline: trend.headline,
      detail: trend.detail,
      reliability: trend.reliability,
    })),
  ]

  const sections: PsychologyReportSection[] = [performanceSection(analytics.baseline)]
  if (checkInSummary.checkInCount > 0) {
    sections.push(checkInSection(checkInSummary))
  }
  if (tradingPsych.followedPlanRate != null || tradingPsych.mostCommonEmotion != null) {
    const disciplineMetrics: PsychologyReportMetricRow[] = []
    if (tradingPsych.followedPlanRate != null) {
      disciplineMetrics.push({
        label: "Followed Plan",
        value: formatPsychologyPercent(tradingPsych.followedPlanRate * 100),
      })
    }
    if (tradingPsych.averageConviction != null) {
      disciplineMetrics.push({
        label: "Avg Conviction",
        value: formatPsychologyRating(tradingPsych.averageConviction),
      })
    }
    if (tradingPsych.averageExecutionRating != null) {
      disciplineMetrics.push({
        label: "Avg Execution",
        value: formatPsychologyRating(tradingPsych.averageExecutionRating),
      })
    }
    sections.push({
      id: "discipline",
      title: "Discipline",
      subtitle: null,
      bullets: [],
      metrics: disciplineMetrics,
    })
    const emotionMetrics: PsychologyReportMetricRow[] = []
    if (tradingPsych.mostCommonEmotion) {
      emotionMetrics.push({ label: "Most Common", value: tradingPsych.mostCommonEmotion })
    }
    if (tradingPsych.fomoTradeCount > 0) {
      emotionMetrics.push({
        label: "FOMO Trades",
        value: formatPsychologyInteger(tradingPsych.fomoTradeCount),
      })
    }
    if (tradingPsych.frustratedTradeCount > 0) {
      emotionMetrics.push({
        label: "Frustrated Trades",
        value: formatPsychologyInteger(tradingPsych.frustratedTradeCount),
      })
    }
    sections.push({
      id: "emotion",
      title: "Emotions",
      subtitle: null,
      bullets: [],
      metrics: emotionMetrics,
    })
  }

  const sleepInsight = facts.topInsights.find((insight) => insight.category === "sleep")
  if (sleepInsight) {
    sections.push({
      id: "sleep",
      title: "Sleep & Performance",
      subtitle: null,
      bullets: [sleepInsight.headline, sleepInsight.detail],
      metrics: [],
    })
  }

  const mental = facts.topInsights.find((insight) => insight.category === "mentalState")
  if (mental) {
    const mentalMetrics: PsychologyReportMetricRow[] = []
    if (checkInSummary.averageEnergy != null) {
      mentalMetrics.push({
        label: "Avg Energy",
        value: formatPsychologyRating(checkInSummary.averageEnergy),
      })
    }
    if (checkInSummary.averageMorningRating != null) {
      mentalMetrics.push({
        label: "Avg Morning",
        value: formatPsychologyRating(checkInSummary.averageMorningRating),
      })
    }
    sections.push({
      id: "mentalState",
      title: "Stress / Focus / Energy",
      subtitle: null,
      bullets: [mental.headline, mental.detail],
      metrics: mentalMetrics,
    })
  }

  if (behavior.afterTwoLossesWinRate != null) {
    const bullets: string[] = []
    if (
      behavior.afterTwoLossesWinRate != null &&
      behavior.afterTwoLossesBaselineWinRate != null
    ) {
      bullets.push(
        `Win rate after 2+ losses: ${formatPsychologyPercent(behavior.afterTwoLossesWinRate * 100)} vs ${formatPsychologyPercent(behavior.afterTwoLossesBaselineWinRate * 100)} baseline`
      )
    }
    sections.push({
      id: "afterLosses",
      title: "After Losses",
      subtitle: null,
      bullets,
      metrics: [],
    })
  }

  if (behavior.earlyTradeAvgPnL != null || behavior.averageTradesPerDay != null) {
    const metrics: PsychologyReportMetricRow[] = []
    if (behavior.averageTradesPerDay != null) {
      metrics.push({
        label: "Trades/Day",
        value: behavior.averageTradesPerDay.toLocaleString("en-US", {
          minimumFractionDigits: 1,
          maximumFractionDigits: 1,
        }),
      })
    }
    if (behavior.earlyTradeAvgPnL != null && behavior.lateTradeAvgPnL != null) {
      metrics.push({
        label: "Trades 1–3 Avg",
        value: formatPsychologyMoney(behavior.earlyTradeAvgPnL),
      })
      metrics.push({
        label: "Trade #5+ Avg",
        value: formatPsychologyMoney(behavior.lateTradeAvgPnL),
      })
    }
    sections.push({
      id: "tradeFrequency",
      title: "Trade Frequency",
      subtitle: null,
      bullets: [],
      metrics,
    })
  }

  if (facts.trends.length) {
    sections.push({
      id: "trends",
      title: "Trends",
      subtitle:
        periodRef.template === "monthly" ? "This period vs prior history" : null,
      bullets: facts.trends.map((trend) => trend.headline),
      metrics: facts.trends.map((trend) => ({
        label: trend.headline,
        value: trend.detail,
      })),
    })
  }

  const recommendations = buildPsychologyRecommendations(facts)
  if (recommendations.length) {
    sections.push({
      id: "recommendations",
      title: "What to Watch",
      subtitle: null,
      bullets: recommendations,
      metrics: [],
    })
  }

  return {
    periodRef,
    reportID: psychologyReportID(periodRef.template, periodRef.periodID),
    title: psychologyReportTitle(periodRef.template),
    dateRangeLabel: bounds.dateRangeLabel,
    periodStartIso: new Date(bounds.startMs).toISOString(),
    periodEndIso: new Date(bounds.endMs).toISOString(),
    generatedAt: now.getTime(),
    factsHash: facts.factsHash,
    checkInSummary,
    tradingPsychology: tradingPsych,
    behavior,
    performance: analytics.baseline,
    comparisons,
    doingWell: summary.doingWell,
    watchItems: summary.watchItems,
    sections: filterSectionsForTemplate(sections, periodRef.template),
  }
}
