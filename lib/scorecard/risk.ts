import type { ScorecardCategoryResult, ScorecardTrade } from "./types.ts"
import { SCORECARD_CATEGORY_WEIGHTS } from "./types.ts"
import { resolveScorecardReliability } from "./reliability.ts"

/**
 * Risk is not scored. Planned R and max R feed the scorecard insight when the
 * average favorable excursion falls short of the target. Outcome stats such as
 * drawdown stay on the dashboard.
 */
export function scoreRiskCategory(
  trades: readonly ScorecardTrade[],
  _maxDrawdown: number,
  _avgWin: number,
  _avgLoss: number
): ScorecardCategoryResult {
  const withPlannedRr = trades.filter((trade) => trade.rr != null && trade.rr > 0)
  return {
    id: "risk",
    title: "Risk Management",
    weight: SCORECARD_CATEGORY_WEIGHTS.risk,
    score: null,
    coveragePercent: 0,
    reliability: resolveScorecardReliability(Math.max(withPlannedRr.length, trades.length)),
    eligible: false,
    subMetrics: [],
    strengths: [],
    weaknesses: [],
    dataGaps: [],
  }
}
