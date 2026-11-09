import {
  consistencyPlanAdherencePool,
  MIN_POST_LOSS_PLAN_TAGGED,
  MIN_TRIPLE_LOSS_WINDOW_PLAN_TAGGED,
  planAdherenceRate,
  postLossPlanObservations,
  tripleLossWindowPlanObservations,
} from "./planAdherence.ts"
import { clampScore, formatPercent, resolveScorecardReliability } from "./reliability.ts"
import type { ScorecardCategoryResult, ScorecardTrade } from "./types.ts"
import {
  SCORECARD_CATEGORY_WEIGHTS,
  SCORECARD_MIN_TRADING_DAYS_OVERALL,
} from "./types.ts"

export function scoreConsistencyCategory(
  trades: readonly ScorecardTrade[],
  tradingDayCount: number,
  postTripleLossWinRate: number | null
): ScorecardCategoryResult {
  const weight = SCORECARD_CATEGORY_WEIGHTS.consistency
  const subMetrics: ScorecardCategoryResult["subMetrics"] = []
  const strengths: string[] = []
  const weaknesses: string[] = []
  const dataGaps: string[] = []

  const daysWithKeys = new Set(
    trades.map((t) => t.tradingDayKey).filter((k): k is string => Boolean(k))
  ).size

  if (tradingDayCount < SCORECARD_MIN_TRADING_DAYS_OVERALL) {
    const dayLabel = SCORECARD_MIN_TRADING_DAYS_OVERALL === 1 ? "day" : "days"
    dataGaps.push(
      `Log trades on at least ${SCORECARD_MIN_TRADING_DAYS_OVERALL} distinct trading ${dayLabel} in this scope.`
    )
  }

  subMetrics.push({
    id: "consistency.active_trading_days",
    label: "Active trading days in scope",
    value: String(tradingDayCount),
    explanation:
      "Days with at least one trade in this filter, sparse schedules and breaks are not penalized.",
    sampleSize: tradingDayCount,
    sampleLabel: "trading days",
  })

  const postLoss = postLossPlanObservations(trades)
  const postLossRate = planAdherenceRate(postLoss)
  if (postLoss.length > 0 && postLossRate != null) {
    subMetrics.push({
      id: "consistency.plan_after_loss",
      label: "Plan followed after a loss (explicit tags)",
      value: formatPercent(postLossRate),
      explanation:
        "Among trades immediately after a losing trade where you tagged plan adherence, behavioral consistency under pressure.",
      sampleSize: postLoss.length,
      sampleLabel: "tagged post-loss trades",
    })
  }

  const tripleWindow = tripleLossWindowPlanObservations(trades)
  const tripleWindowRate = planAdherenceRate(tripleWindow)
  if (tripleWindow.length >= MIN_TRIPLE_LOSS_WINDOW_PLAN_TAGGED && tripleWindowRate != null) {
    subMetrics.push({
      id: "consistency.plan_after_three_losses",
      label: "Plan followed after 3-loss sequence (explicit tags)",
      value: formatPercent(tripleWindowRate),
      explanation:
        "Tagged trades in the recovery window after the first 3-loss run, shown separately; not double-counted in the score pool.",
      sampleSize: tripleWindow.length,
      sampleLabel: "tagged trades in window",
    })
  }

  if (postTripleLossWinRate != null) {
    subMetrics.push({
      id: "streak.after_three_losses_win_rate",
      label: "Win rate after 3 consecutive losses (outcome context)",
      value: formatPercent(postTripleLossWinRate),
      explanation:
        "Performance context only, not part of the consistency score. Does not reflect plan tagging or calendar frequency.",
      sampleSize: trades.length,
      sampleLabel: "trades in scope",
    })
    if (postTripleLossWinRate < 0.45) {
      weaknesses.push(
        "Win rate drops after 3 consecutive losses, consider a pause rule (outcome context)."
      )
    } else if (postTripleLossWinRate >= 0.55) {
      strengths.push("Win rate after 3-loss sequences is stable in this sample (outcome context).")
    }
  }

  const pool = consistencyPlanAdherencePool(trades)
  const poolRate = planAdherenceRate(pool.observations)
  let score: number | null = null
  if (pool.observations.length >= MIN_POST_LOSS_PLAN_TAGGED && poolRate != null) {
    score = clampScore(poolRate * 100)
    if (pool.tripleWindowAddedCount > 0) {
      subMetrics.push({
        id: "consistency.scored_pool",
        label: "Scored post-loss sample (deduplicated)",
        value: formatPercent(poolRate),
        explanation: `${pool.postLossCount} post-loss tagged trade(s)${
          pool.tripleWindowAddedCount > 0
            ? ` plus ${pool.tripleWindowAddedCount} additional tagged trade(s) from the 3-loss window without double-counting.`
            : "."
        }`,
        sampleSize: pool.observations.length,
        sampleLabel: "tagged trades in score pool",
      })
    }
    if (poolRate >= 0.7) {
      strengths.push("You often report following your plan on trades taken after losses.")
    } else if (poolRate < 0.45) {
      weaknesses.push("Plan adherence drops on trades after losses, review pause rules and triggers.")
    }
  } else if (trades.length > 0) {
    dataGaps.push(
      `Tag plan followed / not followed on at least ${MIN_POST_LOSS_PLAN_TAGGED} trades immediately after a loss to score consistency.`
    )
  }

  const reliability =
    pool.observations.length >= MIN_POST_LOSS_PLAN_TAGGED
      ? resolveScorecardReliability(pool.observations.length)
      : "insufficient"

  const eligible = score != null

  const coveragePercent =
    trades.length > 0
      ? clampScore((daysWithKeys / Math.max(tradingDayCount, 1)) * 100)
      : 0

  return {
    id: "consistency",
    title: "Consistency",
    weight,
    score: eligible ? score : null,
    coveragePercent,
    reliability,
    eligible,
    subMetrics,
    strengths,
    weaknesses,
    dataGaps,
  }
}
