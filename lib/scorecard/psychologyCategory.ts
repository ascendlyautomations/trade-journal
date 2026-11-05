import {
  buildEarlyPsychologyInsightCards,
  resolveMatchedDayReliability,
} from "../psychology/dailyPsychologyInsights.ts"
import { buildMatchedTradingDays } from "../psychology/matchedTradingDays.ts"
import { reliabilityLabel as psychCardReliabilityLabel } from "../psychology/reports/metrics.ts"
import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import { psychologyTradeDateKey } from "../psychology/tradeDateKey.ts"
import { clampScore, formatPercent } from "./reliability.ts"
import { resolveScorecardReliability } from "./reliability.ts"
import type { ScorecardCategoryResult, ScorecardTrade } from "./types.ts"
import { SCORECARD_CATEGORY_WEIGHTS } from "./types.ts"

function toTradeWithPnL(trades: readonly ScorecardTrade[]) {
  return trades.map((t) => ({
    id: t.id,
    entry_time: new Date(t.entryTimeMs).toISOString(),
    created_at: new Date(t.entryTimeMs).toISOString(),
    pnl: t.pnl,
    confidence: t.confidence,
    followed_plan: t.followedPlan,
    emotion: null,
  }))
}

export function countEasternCalendarTradingDays(trades: readonly ScorecardTrade[]): number {
  const keys = new Set<string>()
  for (const trade of trades) {
    const key =
      trade.psychologyDayKey ??
      psychologyTradeDateKey({
        entry_time: new Date(trade.entryTimeMs).toISOString(),
        created_at: new Date(trade.entryTimeMs).toISOString(),
      })
    if (key) keys.add(key)
  }
  return keys.size
}

export function scorePsychologyCategory(
  trades: readonly ScorecardTrade[],
  checkIns: readonly TraderDailyCheckIn[],
  _dashboardTradingDayCount: number
): ScorecardCategoryResult {
  const weight = SCORECARD_CATEGORY_WEIGHTS.psychology
  const subMetrics: ScorecardCategoryResult["subMetrics"] = []
  const strengths: string[] = []
  const weaknesses: string[] = []
  const dataGaps: string[] = []

  const easternTradingDays = countEasternCalendarTradingDays(trades)
  const tradeRows = toTradeWithPnL(trades)
  const matchedDays = buildMatchedTradingDays(tradeRows, checkIns)
  const matchedDayCount = matchedDays.length

  const checkInDayCount = new Set(
    checkIns.map((c) => c.checkInDate).filter(Boolean)
  ).size

  subMetrics.push({
    id: "psych.phase1_mode",
    label: "Psychology score (Phase 1)",
    value: "Insights only",
    explanation:
      "No 0–100 psychology score in Phase 1, avoids double-counting plan adherence from Discipline. Patterns and coverage appear below.",
    sampleSize: matchedDayCount,
    sampleLabel: "matched days",
  })

  subMetrics.push({
    id: "psych.matched_days",
    label: "Matched check-in + trade days",
    value: String(matchedDayCount),
    explanation:
      "Eastern calendar days with a complete check-in and at least one trade on the same calendar day.",
    sampleSize: matchedDayCount,
    sampleLabel: "matched days",
  })

  if (easternTradingDays > 0) {
    const checkInCoverage = Math.min(checkInDayCount / easternTradingDays, 1)
    subMetrics.push({
      id: "psych.checkin_coverage",
      label: "Check-in days vs Eastern trade days (coverage)",
      value: formatPercent(checkInCoverage),
      explanation: "Check-in habit relative to days you traded, coverage only.",
      sampleSize: checkInDayCount,
      sampleLabel: "check-in days",
    })
    if (checkInCoverage < 0.2 && easternTradingDays >= 5) {
      dataGaps.push("Complete daily check-ins on days you trade to improve psychology coverage.")
    }
  }

  const dayReliability = resolveMatchedDayReliability(
    matchedDayCount,
    matchedDays.reduce((s, d) => s + d.tradeCount, 0)
  )

  if (matchedDayCount >= 1) {
    const cards = buildEarlyPsychologyInsightCards(tradeRows, checkIns)
    for (const card of cards.filter((c) => c.id.includes(".compare")).slice(0, 2)) {
      strengths.push(
        `${card.headline} (${psychCardReliabilityLabel(card.reliability)}, association, not causation).`
      )
    }
    for (const card of cards.filter((c) => c.id.includes(".poor")).slice(0, 1)) {
      weaknesses.push(
        `${card.headline}: ${card.detail.split("·")[0]?.trim() ?? card.detail} (exploratory).`
      )
    }
    if (cards.some((c) => c.id === "matchedDays.overview") && strengths.length === 0) {
      strengths.push(
        "You have matched check-in days to explore lifestyle inputs alongside trading (associations only)."
      )
    }
  } else {
    dataGaps.push(
      "Log a complete daily check-in on the same Eastern calendar day as a trade to match psychology data."
    )
  }

  const score = null
  const coveragePercent = clampScore(
    easternTradingDays > 0 ? (matchedDayCount / easternTradingDays) * 100 : 0
  )

  const reliability =
    matchedDayCount >= 1 && dayReliability !== "insufficient"
      ? dayReliability
      : resolveScorecardReliability(checkInDayCount)

  const eligible = false

  return {
    id: "psychology",
    title: "Psychology",
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
