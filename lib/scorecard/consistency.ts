import { clampScore, formatPercent, resolveScorecardReliability } from "./reliability.ts"
import type { ScorecardCategoryResult, ScorecardTrade } from "./types.ts"
import { SCORECARD_CATEGORY_WEIGHTS } from "./types.ts"

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

  if (tradingDayCount < 5) {
    dataGaps.push("Log trades on at least 5 distinct trading days in this scope.")
  }

  subMetrics.push({
    id: "consistency.active_trading_days",
    label: "Active trading days in scope",
    value: String(tradingDayCount),
    explanation:
      "Days with at least one trade in this filter — sparse schedules and breaks are not penalized.",
    sampleSize: tradingDayCount,
    sampleLabel: "trading days",
  })

  let streakScore: number | null = null
  if (postTripleLossWinRate != null) {
    streakScore = clampScore(postTripleLossWinRate * 100)
    subMetrics.push({
      id: "streak.after_three_losses",
      label: "Win rate after 3 consecutive losses",
      value: formatPercent(postTripleLossWinRate),
      explanation:
        "Outcome proxy after a 3-loss sequence — reflects tilt/recovery patterns, not calendar frequency or net P&L.",
      sampleSize: trades.length,
      sampleLabel: "trades in scope",
    })
    if (postTripleLossWinRate < 0.45) {
      weaknesses.push(
        "Win rate drops after 3 consecutive losses — consider a pause rule or size reduction."
      )
    } else if (postTripleLossWinRate >= 0.55) {
      strengths.push("You recover reasonably after 3-loss sequences in this sample.")
    }
  } else if (trades.length >= 5) {
    dataGaps.push(
      "No 3-loss sequence in this scope — recovery-after-losses is not scored (not a penalty)."
    )
  }

  const score = streakScore != null ? streakScore : null

  const reliability =
    streakScore != null
      ? resolveScorecardReliability(trades.length)
      : "insufficient"

  const eligible = tradingDayCount >= 5 && trades.length >= 5 && score != null

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
