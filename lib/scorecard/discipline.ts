import { clampScore, formatPercent, resolveScorecardReliability } from "./reliability.ts"
import type { ScorecardCategoryResult, ScorecardTrade } from "./types.ts"
import { SCORECARD_CATEGORY_WEIGHTS } from "./types.ts"

const MIN_PLAN_TAGGED_FOR_SCORE = 3
const MIN_COVERAGE_WARNING_TRADES = 5
const MIN_SECONDARY_INSIGHT = 2

export function scoreDisciplineCategory(trades: readonly ScorecardTrade[]): ScorecardCategoryResult {
  const weight = SCORECARD_CATEGORY_WEIGHTS.discipline
  const subMetrics: ScorecardCategoryResult["subMetrics"] = []
  const strengths: string[] = []
  const weaknesses: string[] = []
  const dataGaps: string[] = []

  const withPlanKnown = trades.filter((t) => t.followedPlan !== null)
  const followed = withPlanKnown.filter((t) => t.followedPlan === true)
  const withConfidence = trades.filter((t) => t.confidence != null && t.confidence >= 1)
  const withExecution = trades.filter(
    (t) => t.executionRating != null && t.executionRating >= 1
  )
  const losses = trades.filter((t) => t.pnl < 0)

  const planCoverage = trades.length ? withPlanKnown.length / trades.length : 0
  subMetrics.push({
    id: "discipline.plan_coverage",
    label: "Trades with plan follow-up logged",
    value: formatPercent(planCoverage),
    explanation:
      "Share of trades with an explicit plan followed / not followed tag. Low coverage means the adherence score may not represent all behavior.",
    sampleSize: withPlanKnown.length,
    sampleLabel: "tagged trades",
  })

  if (planCoverage < 0.5 && trades.length >= MIN_COVERAGE_WARNING_TRADES) {
    weaknesses.push(
      "Plan adherence is tagged on fewer than half of trades, interpret the score cautiously or tag more trades."
    )
  }

  let planScore: number | null = null
  if (withPlanKnown.length >= MIN_PLAN_TAGGED_FOR_SCORE) {
    const rate = followed.length / withPlanKnown.length
    planScore = clampScore(rate * 100)
    subMetrics.push({
      id: "discipline.plan_adherence",
      label: "Plan followed (explicit tags only)",
      value: formatPercent(rate),
      explanation:
        "Share of tagged trades where you marked the plan as followed, missing tags are excluded, not treated as violations.",
      sampleSize: withPlanKnown.length,
      sampleLabel: "tagged trades",
    })
    if (rate >= 0.7) strengths.push("You report following your plan on most explicitly tagged trades.")
    if (rate < 0.45) weaknesses.push("Plan adherence is low on tagged trades, review rules and triggers.")
  } else {
    dataGaps.push(
      `Tag plan followed / not followed on at least ${MIN_PLAN_TAGGED_FOR_SCORE} trades to score discipline.`
    )
  }

  if (losses.length >= MIN_SECONDARY_INSIGHT) {
    const mistakeOnLoss = losses.filter((t) => t.mistakeType).length / losses.length
    subMetrics.push({
      id: "discipline.mistake_logging_coverage",
      label: "Losses with mistake type logged (coverage)",
      value: formatPercent(mistakeOnLoss),
      explanation:
        "Review documentation on losses, logging mistakes supports learning and is not scored as mistake avoidance.",
      sampleSize: losses.length,
      sampleLabel: "losing trades",
    })
  }

  if (withConfidence.length >= MIN_SECONDARY_INSIGHT) {
    subMetrics.push({
      id: "discipline.confidence_coverage",
      label: "Trades with confidence logged (coverage)",
      value: formatPercent(withConfidence.length / trades.length),
      explanation: "Confidence tags are optional context, not part of the discipline score.",
      sampleSize: withConfidence.length,
      sampleLabel: "tagged trades",
    })
  }

  if (withExecution.length >= MIN_SECONDARY_INSIGHT) {
    const avg =
      withExecution.reduce((s, t) => s + (t.executionRating ?? 0), 0) / withExecution.length
    subMetrics.push({
      id: "discipline.execution_rating_coverage",
      label: "Average execution self-rating (coverage)",
      value: `${avg.toFixed(1)} / 5`,
      explanation:
        "Self-rated execution where logged, shown for transparency; not part of the discipline score.",
      sampleSize: withExecution.length,
      sampleLabel: "rated trades",
    })
  }

  const score = planScore

  const coveragePercent = clampScore(
    trades.length > 0 ? (withPlanKnown.length / trades.length) * 100 : 0
  )
  const reliability = resolveScorecardReliability(withPlanKnown.length)
  const eligible =
    withPlanKnown.length >= MIN_PLAN_TAGGED_FOR_SCORE && planScore != null

  return {
    id: "discipline",
    title: "Discipline",
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
