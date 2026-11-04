import { computeDashboardRrTargetAnalysis } from "../dashboardRrTargetAnalysis.ts"
import { clampScore, formatPercent, resolveScorecardReliability } from "./reliability.ts"
import type { ScorecardCategoryResult, ScorecardTrade } from "./types.ts"
import { SCORECARD_CATEGORY_WEIGHTS } from "./types.ts"

function averageLossMagnitude(avgLoss: number): number | null {
  if (!Number.isFinite(avgLoss) || avgLoss === 0) return null
  return Math.abs(avgLoss)
}

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
      "Documentation coverage only — logging planned R:R does not increase your risk score.",
    sampleSize: trades.length,
    sampleLabel: "trades",
  })

  if (withRealizedRr.length >= 1) {
    subMetrics.push({
      id: "risk.realized_rr_coverage",
      label: "Trades with realized R:R",
      value: formatPercent(realizedCoverage),
      explanation: "Coverage for realized R:R from journal or price data when available.",
      sampleSize: withRealizedRr.length,
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

  let lossSizeScore: number | null = null
  const lossMag = averageLossMagnitude(avgLoss)
  if (avgWin > 0 && lossMag != null) {
    const ratio = lossMag / avgWin
    lossSizeScore = clampScore(100 - Math.min(ratio * 50, 85))
    subMetrics.push({
      id: "risk.avg_loss_vs_win",
      label: "Average loss vs average win (outcome proxy)",
      value: `${ratio.toFixed(2)}×`,
      explanation:
        "Compares typical loss size to typical win size in this scope — an outcome proxy, not proof of stop placement or position sizing.",
      sampleSize: trades.length,
      sampleLabel: "trades",
    })
    if (ratio <= 1) {
      strengths.push("Average loss size is in line with average wins in this window.")
    } else if (ratio >= 1.5) {
      weaknesses.push(
        "Average losses exceed average wins in this window — review risk per trade (outcome proxy)."
      )
    }
  } else if (trades.length >= 5) {
    dataGaps.push("Need both wins and losses in scope to compare average loss vs average win.")
  }

  if (maxDrawdown > 0 && trades.length >= 5) {
    subMetrics.push({
      id: "risk.max_drawdown_context",
      label: "Max drawdown in scope (context)",
      value: `$${maxDrawdown.toFixed(0)}`,
      explanation:
        "Peak-to-trough decline on cumulative P&L in this window — informational only; not normalized by account size and not part of the risk score.",
      sampleSize: trades.length,
      sampleLabel: "trades",
    })
  }

  let attainmentScore: number | null = null
  if (rrTarget.pairedCount >= 3 && rrTarget.avgTargetAttainmentRatio != null) {
    const att = rrTarget.avgTargetAttainmentRatio
    attainmentScore = clampScore(Math.min(att * 100, 100))
    subMetrics.push({
      id: "risk.target_attainment",
      label: "Average max R vs planned R (outcome proxy)",
      value: formatPercent(att),
      explanation:
        rrTarget.sampleSummary ??
        "How far price reached relative to planned R on paired trades — outcome proxy, not plan adherence.",
      sampleSize: rrTarget.pairedCount,
      sampleLabel: "paired trades",
    })
  }

  const components = [lossSizeScore, attainmentScore].filter((v): v is number => v != null)

  const score =
    components.length > 0
      ? clampScore(components.reduce((s, v) => s + v, 0) / components.length)
      : null

  const coveragePercent = clampScore(
    ((rrCoverage + realizedCoverage + maxRrCoverage) / 3) * 100
  )

  const reliabilitySample = Math.max(
    lossSizeScore != null ? trades.length : 0,
    rrTarget.pairedCount,
    0
  )
  const reliability =
    reliabilitySample >= 5
      ? resolveScorecardReliability(reliabilitySample)
      : "insufficient"

  const eligible = trades.length >= 5 && score != null && reliability !== "insufficient"

  if (components.length === 0 && trades.length >= 5) {
    dataGaps.push(
      "Risk score needs comparable win/loss sizes or paired planned/max R data — documentation alone is not scored."
    )
  }

  return {
    id: "risk",
    title: "Risk Management",
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
