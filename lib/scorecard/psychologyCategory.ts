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

const MIN_MATCHED_DAYS_FOR_SCORE = 5
const MIN_PLAN_TAGGED_ON_MATCHED = 3

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

function planAdherenceOnMatchedDays(
  trades: readonly ScorecardTrade[],
  matchedDateKeys: ReadonlySet<string>
): { rate: number | null; tagged: number; followed: number } {
  const onMatched = trades.filter((t) => {
    const key =
      t.psychologyDayKey ??
      psychologyTradeDateKey({
        entry_time: new Date(t.entryTimeMs).toISOString(),
      })
    return key && matchedDateKeys.has(key)
  })
  const tagged = onMatched.filter((t) => t.followedPlan !== null)
  if (tagged.length < MIN_PLAN_TAGGED_ON_MATCHED) {
    return { rate: null, tagged: tagged.length, followed: 0 }
  }
  const followed = tagged.filter((t) => t.followedPlan === true).length
  return { rate: followed / tagged.length, tagged: tagged.length, followed }
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
  const matchedDateKeys = new Set(matchedDays.map((d) => d.dateKey))

  const checkInDayCount = new Set(
    checkIns.map((c) => c.checkInDate).filter(Boolean)
  ).size

  subMetrics.push({
    id: "psych.matched_days",
    label: "Matched check-in + trade days",
    value: String(matchedDayCount),
    explanation:
      "Eastern calendar days with a complete check-in and at least one trade keyed to the same calendar day (not the 6 PM ET futures session).",
    sampleSize: matchedDayCount,
    sampleLabel: "matched days",
  })

  if (easternTradingDays > 0) {
    const checkInCoverage = Math.min(checkInDayCount / easternTradingDays, 1)
    subMetrics.push({
      id: "psych.checkin_coverage",
      label: "Check-in days vs Eastern trade days (coverage)",
      value: formatPercent(checkInCoverage),
      explanation:
        "How often you log check-ins relative to calendar days you traded — coverage only, not a behavior score.",
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
        `${card.headline} (${psychCardReliabilityLabel(card.reliability)} — association, not causation).`
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

  const planOnMatched = planAdherenceOnMatchedDays(trades, matchedDateKeys)
  let behaviorScore: number | null = null
  if (
    matchedDayCount >= MIN_MATCHED_DAYS_FOR_SCORE &&
    planOnMatched.rate != null
  ) {
    behaviorScore = clampScore(planOnMatched.rate * 100)
    subMetrics.push({
      id: "psych.plan_on_matched_days",
      label: "Plan followed on matched days (explicit tags)",
      value: formatPercent(planOnMatched.rate),
      explanation:
        "Among trades on check-in matched days where you explicitly tagged plan adherence — behavioral when sample is sufficient.",
      sampleSize: planOnMatched.tagged,
      sampleLabel: "tagged trades on matched days",
    })
  } else if (matchedDayCount >= 1 && matchedDayCount < MIN_MATCHED_DAYS_FOR_SCORE) {
    dataGaps.push(
      `Need at least ${MIN_MATCHED_DAYS_FOR_SCORE} matched check-in days for a psychology behavior score.`
    )
  } else if (matchedDayCount >= MIN_MATCHED_DAYS_FOR_SCORE && planOnMatched.tagged < MIN_PLAN_TAGGED_ON_MATCHED) {
    dataGaps.push(
      `Tag plan followed / not followed on at least ${MIN_PLAN_TAGGED_ON_MATCHED} trades on matched check-in days.`
    )
  }

  const score = behaviorScore

  const coveragePercent = clampScore(
    easternTradingDays > 0 ? (matchedDayCount / easternTradingDays) * 100 : 0
  )

  const reliability =
    matchedDayCount >= 1 && dayReliability !== "insufficient"
      ? dayReliability
      : resolveScorecardReliability(planOnMatched.tagged || checkInDayCount)

  const eligible =
    matchedDayCount >= MIN_MATCHED_DAYS_FOR_SCORE &&
    behaviorScore != null &&
    isDevelopingOrStrongPsych(dayReliability)

  return {
    id: "psychology",
    title: "Psychology",
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

function isDevelopingOrStrongPsych(
  reliability: ReturnType<typeof resolveMatchedDayReliability>
): boolean {
  return reliability === "developing" || reliability === "strong"
}
