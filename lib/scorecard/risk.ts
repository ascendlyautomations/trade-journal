import { computeDashboardRrTargetAnalysis } from "../dashboardRrTargetAnalysis.ts"
import { clampScore, formatPercent, resolveScorecardReliability } from "./reliability.ts"
import type { ScorecardCategoryResult, ScorecardTrade } from "./types.ts"
import { SCORECARD_CATEGORY_WEIGHTS } from "./types.ts"

function averageLossMagnitude(avgLoss: number): number | null {
  if (!Number.isFinite(avgLoss) || avgLoss === 0) return null
  return Math.abs(avgLoss)
}

/**
 * Phase 1: Risk category has no numerical score, `rr` is planned R:R, `realizedRr` is
 * exit/plan-derived realized R (not stop compliance), `maxRrReached` is favorable excursion.
 * None of these reliably prove stop placement; show coverage + outcome context only.
 */
export function scoreRiskCategory(
  trades: readonly ScorecardTrade[],
  maxDrawdown: number,
  avgWin: number,
  avgLoss: number
): ScorecardCategoryResult {
  const weight = SCORECARD_CATEGORY_WEIGHTS.risk
  const subMetrics: ScorecardCategoryResult["subMetrics"] = []
  const strengths: string[] = []
  const weaknesses: string[] = []
  const dataGaps: string[] = []

  const withPlannedRr = trades.filter((t) => t.rr != null && t.rr > 0)
  const withRealizedRr = trades.filter((t) => t.realizedRr != null)
  const withMaxRr = trades.filter((t) => t.maxRrReached != null && t.maxRrReached > 0)

  const rrCoverage = trades.length ? withPlannedRr.length / trades.length : 0
  const realizedCoverage = trades.length ? withRealizedRr.length / trades.length : 0
  const maxRrCoverage = trades.length ? withMaxRr.length / trades.length : 0

  subMetrics.push({
    id: "risk.planned_rr_coverage",
    label: "Trades with planned R:R logged",
    value: formatPercent(rrCoverage),
    explanation:
      "Planned risk/reward target on the trade, documentation coverage only in Phase 1.",
    sampleSize: trades.length,
    sampleLabel: "trades",
  })

  if (withRealizedRr.length >= 1) {
    subMetrics.push({
      id: "risk.realized_rr_coverage",
      label: "Trades with realized R:R",
      value: formatPercent(realizedCoverage),
      explanation:
        "Realized R:R from stored exit data or plan/price math, not scored; does not validate stop placement.",
      sampleSize: withRealizedRr.length,
      sampleLabel: "trades",
    })
  }

  if (withMaxRr.length >= 1) {
    subMetrics.push({
      id: "risk.max_rr_coverage",
      label: "Trades with max R reached logged",
      value: formatPercent(maxRrCoverage),
      explanation:
        "Maximum favorable excursion vs plan, context for review; not exit quality or risk discipline.",
      sampleSize: withMaxRr.length,
      sampleLabel: "trades",
    })
  }

  const dashboardRows = trades.map((t) => ({
    pnl: t.pnl,
    rr: t.rr,
    max_rr_reached: t.maxRrReached,
  }))
  const rrTarget = computeDashboardRrTargetAnalysis(dashboardRows)

  if (rrCoverage < 0.25 && trades.length >= 10) {
    dataGaps.push("Log planned R:R on more trades to improve risk documentation coverage.")
  }

  const lossMag = averageLossMagnitude(avgLoss)
  if (avgWin > 0 && lossMag != null) {
    const ratio = lossMag / avgWin
    subMetrics.push({
      id: "risk.avg_loss_vs_win_context",
      label: "Average loss vs average win (outcome context)",
      value: `${ratio.toFixed(2)}×`,
      explanation:
        "Scope-wide outcome context only, not part of the risk score.",
      sampleSize: trades.length,
      sampleLabel: "trades",
    })
  }

  if (maxDrawdown > 0 && trades.length >= 5) {
    subMetrics.push({
      id: "risk.max_drawdown_context",
      label: "Max drawdown in scope (outcome context)",
      value: `$${maxDrawdown.toFixed(0)}`,
      explanation:
        "Peak-to-trough decline on cumulative P&L, informational; not normalized by account size.",
      sampleSize: trades.length,
      sampleLabel: "trades",
    })
  }

  if (rrTarget.pairedCount >= 3 && rrTarget.avgTargetAttainmentRatio != null) {
    subMetrics.push({
      id: "risk.target_attainment_context",
      label: "Average max R vs planned R (outcome context)",
      value: formatPercent(rrTarget.avgTargetAttainmentRatio),
      explanation:
        rrTarget.sampleSummary ??
        "Price excursion relative to planned R, outcome context only, not scored in Phase 1.",
      sampleSize: rrTarget.pairedCount,
      sampleLabel: "paired trades",
    })
  }

  dataGaps.push(
    "Risk category is insights and coverage only in Phase 1, no numerical score until a defensible behavioral metric exists."
  )

  const score = null

  const coveragePercent = clampScore(
    ((rrCoverage + realizedCoverage + maxRrCoverage) / 3) * 100
  )

  const reliability = resolveScorecardReliability(
    Math.max(withPlannedRr.length, withRealizedRr.length, trades.length)
  )

  const eligible = false

  return {
    id: "risk",
    title: "Risk Management",
    weight,
    score,
    coveragePercent,
    reliability,
    eligible,
    subMetrics,
    strengths,
    weaknesses,
    dataGaps,
  }
}
