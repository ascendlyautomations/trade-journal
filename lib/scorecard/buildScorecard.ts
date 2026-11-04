import {
  isDevelopingOrStrong,
  resolveScorecardReliability,
} from "./reliability.ts"
import { scoreConsistencyCategory } from "./consistency.ts"
import { scoreDisciplineCategory } from "./discipline.ts"
import { scorePsychologyCategory } from "./psychologyCategory.ts"
import { scoreRiskCategory } from "./risk.ts"
import { postTripleLossWinRate } from "./tradeMapping.ts"
import type {
  ScorecardBuildInput,
  ScorecardCategoryResult,
  ScorecardOverallContribution,
  ScorecardResult,
} from "./types.ts"
import {
  SCORECARD_CATEGORY_WEIGHTS,
  SCORECARD_MIN_TRADES_OVERALL,
  SCORECARD_MIN_TRADING_DAYS_OVERALL,
} from "./types.ts"

function computeOverall(
  categories: ScorecardCategoryResult[],
  tradeCount: number,
  tradingDayCount: number
): ScorecardResult["overall"] {
  const scored = categories.filter(
    (c) => c.score != null && c.eligible && c.reliability !== "insufficient"
  )

  const hasDeveloping = categories.some((c) => isDevelopingOrStrong(c.reliability))

  const emptyContributions: ScorecardOverallContribution[] = []

  if (
    tradeCount < SCORECARD_MIN_TRADES_OVERALL ||
    tradingDayCount < SCORECARD_MIN_TRADING_DAYS_OVERALL ||
    !hasDeveloping
  ) {
    const parts: string[] = []
    if (tradeCount < SCORECARD_MIN_TRADES_OVERALL) {
      parts.push(
        `${tradeCount}/${SCORECARD_MIN_TRADES_OVERALL} trades in scope`
      )
    }
    if (tradingDayCount < SCORECARD_MIN_TRADING_DAYS_OVERALL) {
      parts.push(
        `${tradingDayCount}/${SCORECARD_MIN_TRADING_DAYS_OVERALL} trading days`
      )
    }
    if (!hasDeveloping) {
      parts.push("at least one category needs developing-level sample size")
    }
    return {
      score: null,
      status: tradeCount > 0 ? "building" : "unavailable",
      statusMessage: `Building your score — ${parts.join(" · ")}`,
      coveragePercent: 0,
      reliability: resolveScorecardReliability(tradeCount),
      tradeCount,
      tradingDayCount,
      contributions: emptyContributions,
      nominalWeightIncluded: 0,
    }
  }

  if (scored.length === 0) {
    return {
      score: null,
      status: "building",
      statusMessage:
        "Building your score — add journal tags, risk data, and matched check-ins to unlock category scores.",
      coveragePercent: 0,
      reliability: resolveScorecardReliability(tradeCount),
      tradeCount,
      tradingDayCount,
      contributions: emptyContributions,
      nominalWeightIncluded: 0,
    }
  }

  let weightSum = 0
  let weighted = 0
  let nominalIncluded = 0
  const contributions: ScorecardOverallContribution[] = []

  for (const cat of scored) {
    const w = SCORECARD_CATEGORY_WEIGHTS[cat.id]
    weightSum += w
    weighted += w * (cat.score ?? 0)
    nominalIncluded += w
  }

  for (const cat of scored) {
    const w = SCORECARD_CATEGORY_WEIGHTS[cat.id]
    contributions.push({
      id: cat.id,
      title: cat.title,
      score: cat.score ?? 0,
      nominalWeight: w,
      effectiveWeight: w / weightSum,
    })
  }

  const score = Math.round(weighted / weightSum)
  const coveragePercent = Math.round(
    scored.reduce((s, c) => s + c.coveragePercent, 0) / scored.length
  )
  const reliability = scored.reduce<ReturnType<typeof resolveScorecardReliability>>(
    (min, c) => {
      const order = ["insufficient", "earlySignal", "developing", "strong"] as const
      return order.indexOf(c.reliability) < order.indexOf(min) ? c.reliability : min
    },
    "strong"
  )

  let statusMessage = "Overall trading score for the current dashboard scope."
  if (nominalIncluded < 0.999) {
    const pct = Math.round(nominalIncluded * 100)
    statusMessage += ` Based on ${scored.length} of 4 categories (${pct}% of nominal weight) — incomplete coverage is not low performance.`
  }

  return {
    score,
    status: "ready",
    statusMessage,
    coveragePercent,
    reliability,
    tradeCount,
    tradingDayCount,
    contributions,
    nominalWeightIncluded: nominalIncluded,
  }
}

export function buildTradingScorecard(input: ScorecardBuildInput): ScorecardResult {
  const { trades, checkIns, analytics, scopeLabel } = input
  const postLoss = analytics.postTripleLossWinRate ?? postTripleLossWinRate(trades)

  const categories: ScorecardCategoryResult[] = [
    scoreConsistencyCategory(trades, analytics.periodTradingDayCount, postLoss),
    scoreRiskCategory(
      trades,
      analytics.maxDrawdown,
      analytics.avgWin,
      analytics.avgLoss
    ),
    scoreDisciplineCategory(trades),
    scorePsychologyCategory(trades, checkIns, analytics.periodTradingDayCount),
  ]

  const overall = computeOverall(
    categories,
    analytics.totalTrades,
    analytics.periodTradingDayCount
  )

  return {
    scopeLabel,
    generatedAtMs: Date.now(),
    overall,
    categories,
  }
}

export function collectTopStrengthsAndWeaknesses(result: ScorecardResult, limit = 3) {
  const strengths: string[] = []
  const weaknesses: string[] = []
  for (const cat of result.categories) {
    strengths.push(...cat.strengths)
    weaknesses.push(...cat.weaknesses)
  }
  return {
    strengths: strengths.slice(0, limit),
    weaknesses: weaknesses.slice(0, limit),
  }
}
