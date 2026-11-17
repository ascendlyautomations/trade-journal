import { clampScore, formatPercent, resolveScorecardReliability } from "./reliability.ts"
import type { ScorecardCategoryResult, ScorecardTrade } from "./types.ts"
import { SCORECARD_CATEGORY_WEIGHTS } from "./types.ts"

const MIN_PLAN_TAGGED_FOR_SCORE = 3

export function scoreDisciplineCategory(trades: readonly ScorecardTrade[]): ScorecardCategoryResult {
  const weight = SCORECARD_CATEGORY_WEIGHTS.discipline
  const subMetrics: ScorecardCategoryResult["subMetrics"] = []
  const dataGaps: string[] = []

  const withPlanKnown = trades.filter((trade) => trade.followedPlan !== null)
  const followed = withPlanKnown.filter((trade) => trade.followedPlan === true)

  subMetrics.push({
    id: "discipline.plan_coverage",
    label: "Tagged trades",
    value: String(withPlanKnown.length),
    explanation: "Trades with an explicit plan followed or not followed tag.",
    sampleSize: withPlanKnown.length,
    sampleLabel: "tagged trades",
  })

  let planScore: number | null = null
  if (withPlanKnown.length >= MIN_PLAN_TAGGED_FOR_SCORE) {
    const rate = followed.length / withPlanKnown.length
    planScore = clampScore(rate * 100)
    subMetrics.push({
      id: "discipline.plan_adherence",
      label: "Plan followed",
      value: formatPercent(rate),
      explanation: "Share of tagged trades marked as plan followed. Missing tags are excluded.",
      sampleSize: withPlanKnown.length,
      sampleLabel: "tagged trades",
    })
  } else if (trades.length > 0) {
    dataGaps.push(
      `Tag plan followed or not followed on at least ${MIN_PLAN_TAGGED_FOR_SCORE} trades.`
    )
  }

  const eligible = withPlanKnown.length >= MIN_PLAN_TAGGED_FOR_SCORE && planScore != null

  return {
    id: "discipline",
    title: "Discipline",
    weight,
    score: eligible ? planScore : null,
    coveragePercent: clampScore(
      trades.length > 0 ? (withPlanKnown.length / trades.length) * 100 : 0
    ),
    reliability: resolveScorecardReliability(withPlanKnown.length),
    eligible,
    subMetrics,
    strengths: [],
    weaknesses: [],
    dataGaps,
  }
}
