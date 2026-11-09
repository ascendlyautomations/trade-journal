import type { ScorecardTrade } from "./types.ts"

export const MIN_POST_LOSS_PLAN_TAGGED = 3
export const MIN_TRIPLE_LOSS_WINDOW_PLAN_TAGGED = 2

export type PlanAdherenceObservation = {
  tradeId: string
  followed: boolean
  source: "post_loss" | "triple_loss_window"
}

function isTagged(trade: ScorecardTrade): boolean {
  return trade.followedPlan !== null
}

/** First 3-loss sequence recovery window (same indices as win-rate context). */
export function tripleLossRecoveryIndices(
  trades: readonly ScorecardTrade[]
): { start: number; end: number } | null {
  if (trades.length < 4) return null
  for (let i = 0; i <= trades.length - 4; i++) {
    if (trades[i].pnl < 0 && trades[i + 1].pnl < 0 && trades[i + 2].pnl < 0) {
      const start = i + 3
      const end = Math.min(trades.length, start + 5)
      if (start >= end) return null
      return { start, end }
    }
  }
  return null
}

export function postLossPlanObservations(
  trades: readonly ScorecardTrade[]
): PlanAdherenceObservation[] {
  const out: PlanAdherenceObservation[] = []
  for (let i = 1; i < trades.length; i++) {
    if ((trades[i - 1].pnl ?? 0) >= 0) continue
    const trade = trades[i]
    if (!isTagged(trade)) continue
    out.push({
      tradeId: trade.id,
      followed: trade.followedPlan === true,
      source: "post_loss",
    })
  }
  return out
}

export function tripleLossWindowPlanObservations(
  trades: readonly ScorecardTrade[]
): PlanAdherenceObservation[] {
  const window = tripleLossRecoveryIndices(trades)
  if (!window) return []
  const out: PlanAdherenceObservation[] = []
  for (let i = window.start; i < window.end; i++) {
    const trade = trades[i]
    if (!isTagged(trade)) continue
    out.push({
      tradeId: trade.id,
      followed: trade.followedPlan === true,
      source: "triple_loss_window",
    })
  }
  return out
}

/**
 * Observations for consistency scoring: post-loss tagged first; if below minimum,
 * add triple-loss-window tagged trades not already included (dedupe by trade id).
 */
export function consistencyPlanAdherencePool(
  trades: readonly ScorecardTrade[]
): {
  observations: PlanAdherenceObservation[]
  postLossCount: number
  tripleWindowAddedCount: number
} {
  const postLoss = postLossPlanObservations(trades)
  const byId = new Map<string, PlanAdherenceObservation>()
  for (const o of postLoss) {
    byId.set(o.tradeId, o)
  }
  const postLossCount = byId.size

  let tripleWindowAddedCount = 0
  if (byId.size < MIN_POST_LOSS_PLAN_TAGGED) {
    for (const o of tripleLossWindowPlanObservations(trades)) {
      if (!byId.has(o.tradeId)) {
        byId.set(o.tradeId, o)
        tripleWindowAddedCount += 1
      }
    }
  }

  return {
    observations: [...byId.values()],
    postLossCount,
    tripleWindowAddedCount,
  }
}

export function planAdherenceRate(observations: readonly PlanAdherenceObservation[]): number | null {
  if (observations.length === 0) return null
  const followed = observations.filter((o) => o.followed).length
  return followed / observations.length
}
