import { hasStoredRr } from "./tradeRr.ts"

/** Descriptive copy when at least one paired trade exists. */
export const RR_TARGET_MIN_PAIRED_DESCRIPTIVE = 1
/** Actionable recommendations need this many paired trades. */
export const RR_TARGET_MIN_PAIRED_RECOMMEND = 5
/** Bucket hints need this many paired trades in the bucket. */
export const RR_TARGET_MIN_BUCKET = 3

export type DashboardRrTargetAnalysis = {
  /** Trades in scope after dashboard filters (context only). */
  tradeCount: number
  /** Trades with valid targeted R:R (>0) and max R:R reached. */
  pairedCount: number
  pairedNonPositiveCount: number
  pairedPositiveCount: number
  avgTargetRr: number | null
  avgMaxRrReached: number | null
  /** Mean (max ÷ target) on paired trades; may exceed 1 (100%). Not realized P&L. */
  avgTargetAttainmentRatio: number | null
  sampleSummary: string | null
  headline: string | null
  bullets: string[]
}

type TradeLike = {
  rr?: unknown
  max_rr_reached?: unknown
  pnl?: unknown
}

/** Strict eligibility for the R:R Targeting panel only (not dashboard Avg Max R:R KPI). */
export function isRrTargetingEligibleTrade(t: TradeLike): boolean {
  if (!hasStoredRr(t.rr) || !hasStoredRr(t.max_rr_reached)) return false
  const target = Number(t.rr)
  return Number.isFinite(target) && target > 0
}

function targetBucket(target: number): string {
  if (target < 1) return "Under 1R"
  if (target < 2) return "1–2R"
  if (target < 3) return "2–3R"
  if (target < 4) return "3–4R"
  if (target < 5) return "4–5R"
  return "5R+"
}

function formatR(value: number): string {
  return value.toFixed(2).replace(/\.?0+$/, "")
}

function averageOnPaired(
  paired: TradeLike[],
  pick: (target: number, max: number) => number
): number | null {
  if (paired.length === 0) return null
  let sum = 0
  for (const t of paired) {
    const target = Number(t.rr)
    const max = Number(t.max_rr_reached)
    sum += pick(target, max)
  }
  return sum / paired.length
}

function buildSampleSummary(pairedCount: number, tradeCount: number): string {
  const label =
    pairedCount === 1
      ? "Based on 1 trade with both values recorded."
      : `Based on ${pairedCount} trades with both values recorded.`
  if (tradeCount <= pairedCount) return label
  const excluded = tradeCount - pairedCount
  return `${label} (${excluded} other filtered trade${excluded === 1 ? "" : "s"} excluded — missing target or max R:R.)`
}

export function computeDashboardRrTargetAnalysis(
  trades: TradeLike[]
): DashboardRrTargetAnalysis {
  const tradeCount = trades.length
  const paired = trades.filter(isRrTargetingEligibleTrade)

  let pairedNonPositiveCount = 0
  let pairedPositiveCount = 0
  for (const t of paired) {
    if ((Number(t.pnl) || 0) > 0) pairedPositiveCount += 1
    else pairedNonPositiveCount += 1
  }

  const emptyMetrics = {
    avgTargetRr: null as number | null,
    avgMaxRrReached: null as number | null,
    avgTargetAttainmentRatio: null as number | null,
  }

  const base: DashboardRrTargetAnalysis = {
    tradeCount,
    pairedCount: paired.length,
    pairedNonPositiveCount,
    pairedPositiveCount,
    ...emptyMetrics,
    sampleSummary: null,
    headline: null,
    bullets: [],
  }

  if (paired.length < RR_TARGET_MIN_PAIRED_DESCRIPTIVE) {
    base.headline = "Record both values to unlock R:R Targeting."
    base.bullets = [
      "This panel only includes trades with Targeted Risk/Reward and Max R:R Reached. Add both on the same trade — max R:R is usually recorded on losses and breakevens.",
    ]
    if (tradeCount > 0) {
      base.bullets.push(
        `${tradeCount} trade${tradeCount === 1 ? "" : "s"} match your current filters; none have both fields yet.`,
      )
    }
    return base
  }

  base.avgTargetRr = averageOnPaired(paired, (target) => target)
  base.avgMaxRrReached = averageOnPaired(paired, (_t, max) => max)
  base.avgTargetAttainmentRatio = averageOnPaired(paired, (target, max) =>
    max / target
  )
  base.sampleSummary = buildSampleSummary(paired.length, tradeCount)

  const attainment = base.avgTargetAttainmentRatio
  const attainmentPct =
    attainment != null ? Math.round(attainment * 100) : null
  const canRecommend = paired.length >= RR_TARGET_MIN_PAIRED_RECOMMEND
  const descriptiveOnly = !canRecommend

  if (
    attainmentPct != null &&
    base.avgMaxRrReached != null &&
    base.avgTargetRr != null
  ) {
    const prefix = descriptiveOnly
      ? "Early read (small sample):"
      : "In this paired sample,"
    base.bullets.push(
      `${prefix} average target attainment is ${attainmentPct}% (${formatR(base.avgMaxRrReached)}R max reached vs ${formatR(base.avgTargetRr)}R targeted). Values above 100% mean price exceeded the target before exit.`,
    )
  }

  const bucketStats: Record<
    string,
    { trades: number; wins: number; targetSum: number; maxSum: number }
  > = {}

  for (const t of paired) {
    const target = Number(t.rr)
    const max = Number(t.max_rr_reached)
    const label = targetBucket(target)
    if (!bucketStats[label]) {
      bucketStats[label] = { trades: 0, wins: 0, targetSum: 0, maxSum: 0 }
    }
    const b = bucketStats[label]
    b.trades += 1
    b.targetSum += target
    b.maxSum += max
    if ((Number(t.pnl) || 0) > 0) b.wins += 1
  }

  if (canRecommend && attainment != null && attainment < 0.85 && base.avgTargetRr != null) {
    const suggested = Math.max(
      0.5,
      Math.round(base.avgTargetRr * attainment * 2) / 2
    )
    base.bullets.push(
      `Among these ${paired.length} trades, price often reversed before the full target — exits planned nearer ${formatR(suggested)}R may align with typical extension (not a profit guarantee).`,
    )
  }

  if (canRecommend && base.avgTargetRr != null) {
    let bestWin: {
      label: string
      winRate: number
      avgTarget: number
      trades: number
    } | null = null
    for (const [label, b] of Object.entries(bucketStats)) {
      if (b.trades >= RR_TARGET_MIN_BUCKET) {
        const winRate = b.wins / b.trades
        const avgTarget = b.targetSum / b.trades
        if (!bestWin || winRate > bestWin.winRate) {
          bestWin = { label, winRate, avgTarget, trades: b.trades }
        }
      }
    }
    if (
      bestWin &&
      Math.abs(bestWin.avgTarget - base.avgTargetRr) > 0.4 &&
      bestWin.winRate >= 0.45
    ) {
      const wrPct = Math.round(bestWin.winRate * 100)
      base.bullets.push(
        `Among paired trades, ${bestWin.label} targets (${bestWin.trades} trades) show a ${wrPct}% win rate vs ${formatR(base.avgTargetRr)}R average target in this sample — consider whether ~${formatR(bestWin.avgTarget)}R plans fit your edge.`,
      )
    }
  }

  if (canRecommend) {
    for (const [label, b] of Object.entries(bucketStats)) {
      if (b.trades >= RR_TARGET_MIN_BUCKET) {
        const avgMax = b.maxSum / b.trades
        const avgTarget = b.targetSum / b.trades
        if (avgTarget >= 3 && avgMax < avgTarget * 0.7) {
          base.bullets.push(
            `For ${label} targets (${b.trades} paired trades), price peaked around ${formatR(avgMax)}R before exit while targeting ~${formatR(avgTarget)}R — partials or trails may protect open heat.`,
          )
          break
        }
      }
    }
  }

  if (descriptiveOnly && base.bullets.length <= 2) {
    base.bullets.push(
      `Add ${RR_TARGET_MIN_PAIRED_RECOMMEND - paired.length} more trade${RR_TARGET_MIN_PAIRED_RECOMMEND - paired.length === 1 ? "" : "s"} with both values recorded for stronger recommendations.`,
    )
  }

  if (base.avgTargetRr != null && base.avgMaxRrReached != null) {
    if (
      canRecommend &&
      base.avgTargetRr >= 4 &&
      base.avgMaxRrReached <= base.avgTargetRr * 0.6
    ) {
      base.headline = "High targets vs extension in paired sample"
    } else if (attainment != null && attainment >= 0.9) {
      base.headline = "Target attainment aligns with how far paired trades ran"
    } else {
      base.headline = "Target attainment (paired trades only)"
    }
  }

  return base
}
