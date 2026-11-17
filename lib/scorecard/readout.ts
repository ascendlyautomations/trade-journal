import { isCompleteCheckIn } from "../dailyCheckIn/validation.ts"
import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import { computeDashboardRrTargetAnalysis } from "../dashboardRrTargetAnalysis.ts"
import {
  evaluatePreferenceCompliance,
  formatComplianceR,
  type PreferenceRuleContext,
} from "../analytics/preferenceCompliance.ts"
import { psychologyTradeDateKey } from "../psychology/tradeDateKey.ts"
import {
  planAdherenceRate,
  postLossPlanObservations,
  MIN_POST_LOSS_PLAN_TAGGED,
} from "./planAdherence.ts"
import { formatPercent } from "./reliability.ts"
import type { ScorecardAdherenceReadout, ScorecardInsight, ScorecardTrade } from "./types.ts"

const MIN_PLAN_TAGS = 3
const MIN_PLAN_GAP = 0.08
const MIN_RR_PAIRS = 5
const MAX_SHORT_ATTAINMENT = 0.8

function psychologyDayKey(trade: ScorecardTrade): string | null {
  if (trade.psychologyDayKey) return trade.psychologyDayKey
  return (
    psychologyTradeDateKey({
      entry_time: new Date(trade.entryTimeMs).toISOString(),
      created_at: new Date(trade.entryTimeMs).toISOString(),
    }) || null
  )
}

export function scorecardCheckInCoverage(
  trades: readonly ScorecardTrade[],
  checkIns: readonly TraderDailyCheckIn[]
): { matchedDays: number; tradingDays: number } {
  const completeDates = new Set(
    checkIns.filter(isCompleteCheckIn).map((checkIn) => checkIn.checkInDate)
  )
  const tradingDays = new Set<string>()
  const matchedDays = new Set<string>()
  for (const trade of trades) {
    const key = psychologyDayKey(trade)
    if (!key) continue
    tradingDays.add(key)
    if (completeDates.has(key)) matchedDays.add(key)
  }
  return { matchedDays: matchedDays.size, tradingDays: tradingDays.size }
}

function planReadout(
  id: ScorecardAdherenceReadout["id"],
  label: string,
  followed: number,
  tagged: number,
  minimum: number,
  pendingNoun: string
): ScorecardAdherenceReadout {
  if (tagged >= minimum) {
    return {
      id,
      label,
      value: formatPercent(followed / tagged),
      pending: null,
      sample: `${tagged} ${pendingNoun}`,
    }
  }
  return {
    id,
    label,
    value: null,
    pending: `${tagged} of ${minimum} ${pendingNoun}`,
    sample: null,
  }
}

export function buildScorecardAdherence(
  trades: readonly ScorecardTrade[],
  checkIns: readonly TraderDailyCheckIn[]
): ScorecardAdherenceReadout[] {
  const tagged = trades.filter((trade) => trade.followedPlan !== null)
  const followed = tagged.filter((trade) => trade.followedPlan === true).length
  const postLoss = postLossPlanObservations(trades)
  const postLossFollowed = postLoss.filter((row) => row.followed).length
  const coverage = scorecardCheckInCoverage(trades, checkIns)

  return [
    planReadout("plan_overall", "Plan followed", followed, tagged.length, MIN_PLAN_TAGS, "tagged trades"),
    planReadout(
      "plan_after_loss",
      "After a loss",
      postLossFollowed,
      postLoss.length,
      MIN_POST_LOSS_PLAN_TAGGED,
      "post-loss tags"
    ),
    {
      id: "check_in",
      label: "Check-ins",
      value:
        coverage.tradingDays > 0
          ? `${coverage.matchedDays} of ${coverage.tradingDays} trading days`
          : "No trading days in this scope",
      pending: null,
      sample: null,
    },
  ]
}

export function buildScorecardInsights(
  trades: readonly ScorecardTrade[],
  preferences: PreferenceRuleContext | null = null
): ScorecardInsight[] {
  const insights: ScorecardInsight[] = []
  const tagged = trades.filter((trade) => trade.followedPlan !== null)
  const postLoss = postLossPlanObservations(trades)
  const overallRate = tagged.length > 0 ? tagged.filter((trade) => trade.followedPlan).length / tagged.length : null
  const afterRate = planAdherenceRate(postLoss)
  if (
    overallRate != null &&
    afterRate != null &&
    tagged.length >= MIN_PLAN_TAGS &&
    postLoss.length >= MIN_POST_LOSS_PLAN_TAGGED &&
    afterRate <= overallRate - MIN_PLAN_GAP
  ) {
    insights.push({
      id: "plan_after_loss",
      text: `Plan adherence has been lower on trades taken after a loss. A pause before the next trade may help you stay with the plan. Based on ${postLoss.length} post-loss tags and ${tagged.length} tagged trades.`,
    })
  }

  const rrTarget = computeDashboardRrTargetAnalysis(
    trades.map((trade) => ({
      pnl: trade.pnl,
      rr: trade.rr,
      max_rr_reached: trade.maxRrReached,
    }))
  )
  const personal = preferences
    ? evaluatePreferenceCompliance(
        trades.map((trade) => ({
          tradeId: trade.id,
          atMs: trade.entryTimeMs,
          accountId: null,
          session: null,
          symbol: null,
          pnl: null,
          easternMinute: null,
          dayKey: trade.psychologyDayKey ?? "unknown",
          weekKey: null,
          weekday: null,
          maxRr: trade.maxRrReached,
          plannedRr: trade.rr != null && trade.rr > 0 ? trade.rr : null,
          contracts: null,
          dollarRisk: null,
        })),
        preferences
      )
    : null
  if (
    personal &&
    personal.uniformTargetRr != null &&
    personal.avgMaxRr != null &&
    personal.avgMaxRr < personal.uniformTargetRr &&
    personal.targetPaired >= MIN_RR_PAIRS
  ) {
    insights.push({
      id: "max_r_shortfall",
      text: `Average max R was ${formatComplianceR(personal.avgMaxRr)}, short of your ${formatComplianceR(personal.uniformTargetRr)}R target. Based on ${personal.targetPaired} trades with a recorded max R.`,
    })
  } else if (
    !personal?.targetPaired &&
    rrTarget.pairedCount >= MIN_RR_PAIRS &&
    rrTarget.avgTargetAttainmentRatio != null &&
    rrTarget.avgTargetAttainmentRatio < MAX_SHORT_ATTAINMENT
  ) {
    insights.push({
      id: "max_r_shortfall",
      text: `Maximum favorable R has been coming in short of the planned target. Reviewing whether those targets are realistic may help. Based on ${rrTarget.pairedCount} trades with both a target and a max R.`,
    })
  }

  return insights
}
