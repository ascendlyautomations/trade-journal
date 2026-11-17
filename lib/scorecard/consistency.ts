import {
  consistencyPlanAdherencePool,
  MIN_POST_LOSS_PLAN_TAGGED,
  planAdherenceRate,
  postLossPlanObservations,
} from "./planAdherence.ts"
import { clampScore, formatPercent, resolveScorecardReliability } from "./reliability.ts"
import type { ScorecardCategoryResult, ScorecardTrade } from "./types.ts"
import { SCORECARD_CATEGORY_WEIGHTS } from "./types.ts"

export function scoreConsistencyCategory(
  trades: readonly ScorecardTrade[],
  _tradingDayCount: number,
  _postTripleLossWinRate: number | null
): ScorecardCategoryResult {
  const weight = SCORECARD_CATEGORY_WEIGHTS.consistency
  const subMetrics: ScorecardCategoryResult["subMetrics"] = []
  const dataGaps: string[] = []

  const postLoss = postLossPlanObservations(trades)
  const postLossRate = planAdherenceRate(postLoss)
  if (postLoss.length > 0 && postLossRate != null) {
    subMetrics.push({
      id: "consistency.plan_after_loss",
      label: "Plan followed after a loss",
      value: formatPercent(postLossRate),
      explanation: "Share of tagged trades taken immediately after a loss where the plan was followed.",
      sampleSize: postLoss.length,
      sampleLabel: "post-loss tags",
    })
  }

  const pool = consistencyPlanAdherencePool(trades)
  const poolRate = planAdherenceRate(pool.observations)
  let score: number | null = null
  if (pool.observations.length >= MIN_POST_LOSS_PLAN_TAGGED && poolRate != null) {
    score = clampScore(poolRate * 100)
  } else if (trades.length > 0) {
    dataGaps.push(
      `Tag plan followed or not followed on at least ${MIN_POST_LOSS_PLAN_TAGGED} trades immediately after a loss.`
    )
  }

  const reliability =
    pool.observations.length >= MIN_POST_LOSS_PLAN_TAGGED
      ? resolveScorecardReliability(pool.observations.length)
      : "insufficient"
  const eligible = score != null

  return {
    id: "consistency",
    title: "Consistency",
    weight,
    score: eligible ? score : null,
    coveragePercent: eligible ? (score ?? 0) : 0,
    reliability,
    eligible,
    subMetrics,
    strengths: [],
    weaknesses: [],
    dataGaps,
  }
}
