import { TRADE_REVIEW_EMOTIONS } from "./catalog.ts"
import type { TraderDailyCheckIn } from "../../dailyCheckIn/types.ts"
import { isCompleteCheckIn } from "../../dailyCheckIn/validation.ts"
import { psychologyTradeDateKey } from "../tradeDateKey.ts"
import type {
  PsychologyAnalyticsSection,
  PsychologyCoachGuardrailFacts,
  PsychologyEnrichedTrade,
  PsychologyGroupMetrics,
  PsychologyInsightCard,
  PsychologyInsightCategory,
  PsychologyReportTrade,
  PsychologySampleReliability,
} from "./types.ts"
import { psychologyTradeMetrics } from "./metrics.ts"
import {
  currentPsychologyRules,
  psychologyRulesAt,
  type PreferenceRuleContext,
  type PsychologyRuleSnapshot,
} from "@/lib/analytics/preferenceCompliance.ts"

export type PsychologyRuleLookup = (
  row: PsychologyEnrichedTrade
) => PsychologyRuleSnapshot

/** Psychology Insights require this many trades on each side. */
export const PSYCHOLOGY_INSIGHT_MIN_TRADES = 8
/** Advanced comparisons can show numbers once each side clears this count. */
export const PSYCHOLOGY_ADVANCED_MIN_TRADES = 5
export const PSYCHOLOGY_MIN_WIN_RATE_GAP = 0.08
/** Absolute average-P&L gap that can qualify on its own, before the relative floor. */
export const PSYCHOLOGY_MIN_AVG_PNL_GAP = 15
export const PSYCHOLOGY_PNL_GAP_RATIO = 0.25
export const PSYCHOLOGY_EARLY_MAX_TRADES = 19
export const PSYCHOLOGY_INSIGHT_LIMIT = 3

const STRAINED_EMOTIONS = new Set([
  "Fearful",
  "FOMO",
  "Frustrated",
  "Hesitant",
  "Overconfident",
])

export type PsychologyPerformanceGap = {
  winRateGap: number
  averagePnLGap: number | null
  pnlMaterial: boolean
  material: boolean
}

type Side = {
  label: string
  sampleLabel: string
  metrics: PsychologyGroupMetrics
}

type CopyPair = {
  headline: string
  suggestion: string
}

type ComparisonDraft = {
  id: string
  category: PsychologyInsightCategory
  title: string
  left: Side
  right: Side
  /** Left is the favorable behavior (high conviction, low stress, plan followed). */
  favorable: "left" | "right"
  whenLeftLeads: { pnl: CopyPair; winRate: CopyPair }
  whenRightLeads: { pnl: CopyPair; winRate: CopyPair }
  rank: number
}

export type ResolvedPsychologyComparison = ComparisonDraft & {
  leader: "left" | "right"
  byWinRateOnly: boolean
  gap: PsychologyPerformanceGap
  headline: string
  suggestion: string
  sampleLine: string
  early: boolean
}

export function averagePnLGapIsMaterial(a: number, b: number): boolean {
  const gap = Math.abs(a - b)
  const scale = Math.max(Math.abs(a), Math.abs(b))
  return gap >= Math.max(PSYCHOLOGY_MIN_AVG_PNL_GAP, scale * PSYCHOLOGY_PNL_GAP_RATIO)
}

export function psychologyPerformanceGap(
  a: PsychologyGroupMetrics,
  b: PsychologyGroupMetrics
): PsychologyPerformanceGap {
  const winRateGap =
    a.winRate == null || b.winRate == null ? 0 : Math.abs(a.winRate - b.winRate)
  const averagePnLGap =
    a.averagePnL == null || b.averagePnL == null
      ? null
      : Math.abs(a.averagePnL - b.averagePnL)
  const pnlMaterial =
    a.averagePnL != null &&
    b.averagePnL != null &&
    averagePnLGapIsMaterial(a.averagePnL, b.averagePnL)
  return {
    winRateGap,
    averagePnLGap,
    pnlMaterial,
    material: pnlMaterial || winRateGap >= PSYCHOLOGY_MIN_WIN_RATE_GAP,
  }
}

function leaderOf(
  left: PsychologyGroupMetrics,
  right: PsychologyGroupMetrics,
  gap: PsychologyPerformanceGap
): { side: "left" | "right"; byWinRateOnly: boolean } | null {
  if (!gap.material) return null
  if (
    gap.pnlMaterial &&
    left.averagePnL != null &&
    right.averagePnL != null &&
    left.averagePnL !== right.averagePnL
  ) {
    return {
      side: left.averagePnL > right.averagePnL ? "left" : "right",
      byWinRateOnly: false,
    }
  }
  if (
    left.winRate != null &&
    right.winRate != null &&
    Math.abs(left.winRate - right.winRate) >= PSYCHOLOGY_MIN_WIN_RATE_GAP
  ) {
    return {
      side: left.winRate > right.winRate ? "left" : "right",
      byWinRateOnly: true,
    }
  }
  return null
}

function tradeWord(count: number): string {
  return count === 1 ? "trade" : "trades"
}

export function psychologySampleLine(
  left: Side,
  right: Side,
  early: boolean
): string {
  const body = `Based on ${left.metrics.tradeCount} ${left.sampleLabel} ${tradeWord(left.metrics.tradeCount)} and ${right.metrics.tradeCount} ${right.sampleLabel} ${tradeWord(right.metrics.tradeCount)}.`
  return early ? `Early read, ${body.charAt(0).toLowerCase()}${body.slice(1)}` : body
}

function reliabilityFor(minCount: number): PsychologySampleReliability {
  return minCount <= PSYCHOLOGY_EARLY_MAX_TRADES ? "earlySignal" : "strong"
}

function sideFrom(
  label: string,
  sampleLabel: string,
  rows: readonly PsychologyEnrichedTrade[]
): Side {
  return {
    label,
    sampleLabel,
    metrics: psychologyTradeMetrics(rows.map((row) => row.trade)),
  }
}

function consider(draft: ComparisonDraft): ResolvedPsychologyComparison | null {
  const minCount = Math.min(draft.left.metrics.tradeCount, draft.right.metrics.tradeCount)
  if (minCount < PSYCHOLOGY_ADVANCED_MIN_TRADES) return null
  const gap = psychologyPerformanceGap(draft.left.metrics, draft.right.metrics)
  const leader = leaderOf(draft.left.metrics, draft.right.metrics, gap)
  if (!leader) return null
  const pack = leader.side === "left" ? draft.whenLeftLeads : draft.whenRightLeads
  const copy = leader.byWinRateOnly ? pack.winRate : pack.pnl
  const early = minCount <= PSYCHOLOGY_EARLY_MAX_TRADES
  return {
    ...draft,
    leader: leader.side,
    byWinRateOnly: leader.byWinRateOnly,
    gap,
    headline: copy.headline,
    suggestion: copy.suggestion,
    sampleLine: psychologySampleLine(draft.left, draft.right, early),
    early,
  }
}

function ratingCopy(
  favorableName: string,
  weakerName: string
): Pick<ComparisonDraft, "whenLeftLeads" | "whenRightLeads"> {
  return {
    whenLeftLeads: {
      pnl: {
        headline: `You've performed better on ${favorableName} days.`,
        suggestion: `Treating ${weakerName} days as higher risk may help.`,
      },
      winRate: {
        headline: `You've won more often on ${favorableName} days.`,
        suggestion: `Treating ${weakerName} days as higher risk may help.`,
      },
    },
    whenRightLeads: {
      pnl: {
        headline: `${weakerName[0]?.toUpperCase()}${weakerName.slice(1)} days have performed better in this sample.`,
        suggestion: `${favorableName[0]?.toUpperCase()}${favorableName.slice(1)} has not lined up with better results here.`,
      },
      winRate: {
        headline: `${weakerName[0]?.toUpperCase()}${weakerName.slice(1)} days have won more often in this sample.`,
        suggestion: `${favorableName[0]?.toUpperCase()}${favorableName.slice(1)} has not lined up with more wins here.`,
      },
    },
  }
}

function bandRows(
  enriched: readonly PsychologyEnrichedTrade[],
  read: (row: PsychologyEnrichedTrade) => number | null,
  highWhen: (value: number) => boolean,
  lowWhen: (value: number) => boolean
): { high: PsychologyEnrichedTrade[]; low: PsychologyEnrichedTrade[] } {
  const high: PsychologyEnrichedTrade[] = []
  const low: PsychologyEnrichedTrade[] = []
  for (const row of enriched) {
    const value = read(row)
    if (value == null) continue
    if (highWhen(value)) high.push(row)
    else if (lowWhen(value)) low.push(row)
  }
  return { high, low }
}

function normalizedEmotion(raw: string | null | undefined): string | null {
  const trimmed = String(raw ?? "").trim()
  if (!trimmed) return null
  return (
    TRADE_REVIEW_EMOTIONS.find((emotion) => emotion.toLowerCase() === trimmed.toLowerCase()) ??
    trimmed
  )
}

function collectComparisons(
  enriched: readonly PsychologyEnrichedTrade[],
  rulesFor: PsychologyRuleLookup = () => ({
    consecutiveLossPause: null,
    maxTradesPerDay: null,
    waitAfterLossMinutes: null,
  })
): ResolvedPsychologyComparison[] {
  const drafts: ComparisonDraft[] = []

  const shortSleep = enriched.filter((row) => {
    const hours = row.dailyCheckIn?.sleepHours
    return hours != null && hours < 6
  })
  const rested = enriched.filter((row) => {
    const hours = row.dailyCheckIn?.sleepHours
    return hours != null && hours >= 7
  })
  drafts.push({
    id: "sleep",
    category: "sleep",
    title: "Sleep",
    left: sideFrom("7h or more", "better-rested", rested),
    right: sideFrom("Under 6h", "short-sleep", shortSleep),
    favorable: "left",
    rank: 20,
    whenLeftLeads: {
      pnl: {
        headline: "You've performed better when you slept at least 7 hours.",
        suggestion: "Protecting sleep before the session may be worth prioritizing.",
      },
      winRate: {
        headline: "You've won more often when you slept at least 7 hours.",
        suggestion: "Protecting sleep before the session may be worth prioritizing.",
      },
    },
    whenRightLeads: {
      pnl: {
        headline: "Shorter sleep has lined up with better results in this sample.",
        suggestion: "Sleep has not been the limiter in these trades.",
      },
      winRate: {
        headline: "Shorter sleep has lined up with more wins in this sample.",
        suggestion: "Sleep has not been the limiter in these trades.",
      },
    },
  })

  const ratingSpecs: Array<{
    id: string
    title: string
    read: (row: PsychologyEnrichedTrade) => number | null
    favorable: string
    weaker: string
    highLabel: string
    lowLabel: string
    highSample: string
    lowSample: string
    rank: number
    invert?: boolean
  }> = [
    {
      id: "focus",
      title: "Focus",
      read: (row) => row.dailyCheckIn?.focusLevel ?? null,
      favorable: "higher-focus",
      weaker: "lower-focus",
      highLabel: "Focus 4–5",
      lowLabel: "Focus 1–2",
      highSample: "higher-focus",
      lowSample: "lower-focus",
      rank: 30,
    },
    {
      id: "energy",
      title: "Energy",
      read: (row) => row.dailyCheckIn?.energyLevel ?? null,
      favorable: "higher-energy",
      weaker: "lower-energy",
      highLabel: "Energy 4–5",
      lowLabel: "Energy 1–2",
      highSample: "higher-energy",
      lowSample: "lower-energy",
      rank: 40,
    },
    {
      id: "morning",
      title: "Morning",
      read: (row) => row.dailyCheckIn?.morningRating ?? null,
      favorable: "stronger-morning",
      weaker: "low-morning",
      highLabel: "Morning 4–5",
      lowLabel: "Morning 1–2",
      highSample: "stronger-morning",
      lowSample: "low-morning",
      rank: 50,
    },
    {
      id: "sleepQuality",
      title: "Sleep quality",
      read: (row) => row.dailyCheckIn?.sleepQuality ?? null,
      favorable: "better sleep-quality",
      weaker: "poor sleep-quality",
      highLabel: "Sleep quality 4–5",
      lowLabel: "Sleep quality 1–2",
      highSample: "better sleep-quality",
      lowSample: "poor sleep-quality",
      rank: 25,
    },
  ]

  for (const spec of ratingSpecs) {
    const bands = bandRows(enriched, spec.read, (value) => value >= 4, (value) => value <= 2)
    const copy = ratingCopy(spec.favorable, spec.weaker)
    drafts.push({
      id: spec.id,
      category: "mentalState",
      title: spec.title,
      left: sideFrom(spec.highLabel, spec.highSample, bands.high),
      right: sideFrom(spec.lowLabel, spec.lowSample, bands.low),
      favorable: "left",
      rank: spec.rank,
      ...copy,
    })
  }

  const stress = bandRows(
    enriched,
    (row) => row.dailyCheckIn?.stressLevel ?? null,
    (value) => value <= 2,
    (value) => value >= 4
  )
  drafts.push({
    id: "stress",
    category: "mentalState",
    title: "Stress",
    left: sideFrom("Stress 1–2", "lower-stress", stress.high),
    right: sideFrom("Stress 4–5", "higher-stress", stress.low),
    favorable: "left",
    rank: 15,
    whenLeftLeads: {
      pnl: {
        headline: "You've performed better on lower-stress days.",
        suggestion: "A short reset when stress is high may help.",
      },
      winRate: {
        headline: "You've won more often on lower-stress days.",
        suggestion: "A short reset when stress is high may help.",
      },
    },
    whenRightLeads: {
      pnl: {
        headline: "Higher-stress days have performed better in this sample.",
        suggestion: "Stress has not lined up with weaker results here.",
      },
      winRate: {
        headline: "Higher-stress days have won more often in this sample.",
        suggestion: "Stress has not lined up with weaker results here.",
      },
    },
  })

  const highConviction = enriched.filter((row) => {
    const confidence = row.trade.confidence
    return confidence != null && confidence >= 4
  })
  const lowConviction = enriched.filter((row) => {
    const confidence = row.trade.confidence
    return confidence != null && confidence >= 1 && confidence <= 2
  })
  drafts.push({
    id: "conviction",
    category: "conviction",
    title: "Conviction",
    left: sideFrom("Conviction 4–5", "higher-conviction", highConviction),
    right: sideFrom("Conviction 1–2", "lower-conviction", lowConviction),
    favorable: "left",
    rank: 10,
    whenLeftLeads: {
      pnl: {
        headline: "Your higher-conviction trades have performed better.",
        suggestion: "Being more selective when confidence is low may help.",
      },
      winRate: {
        headline: "Your higher-conviction trades have won more often.",
        suggestion: "Being more selective when confidence is low may help.",
      },
    },
    whenRightLeads: {
      pnl: {
        headline: "Your lower-conviction trades have performed better in this sample.",
        suggestion:
          "High confidence has not lined up with better results, so it may be worth reviewing what conviction means before you size up.",
      },
      winRate: {
        headline: "Your lower-conviction trades have won more often in this sample.",
        suggestion:
          "High confidence has not lined up with more wins, so it may be worth reviewing what conviction means before you size up.",
      },
    },
  })

  const followed = enriched.filter((row) => row.trade.followedPlan === true)
  const broken = enriched.filter((row) => row.trade.followedPlan === false)
  drafts.push({
    id: "discipline",
    category: "discipline",
    title: "Plan",
    left: sideFrom("Followed plan", "plan-followed", followed),
    right: sideFrom("Off plan", "off-plan", broken),
    favorable: "left",
    rank: 12,
    whenLeftLeads: {
      pnl: {
        headline: "Trades where you followed your plan have performed better.",
        suggestion: "Staying with the plan looks like part of your edge.",
      },
      winRate: {
        headline: "Trades where you followed your plan have won more often.",
        suggestion: "Staying with the plan looks like part of your edge.",
      },
    },
    whenRightLeads: {
      pnl: {
        headline: "Trades marked off your plan have performed better in this sample.",
        suggestion: "Review those trades before treating a plan break as the main problem.",
      },
      winRate: {
        headline: "Trades marked off your plan have won more often in this sample.",
        suggestion: "Review those trades before treating a plan break as the main problem.",
      },
    },
  })

  const byEmotion = new Map<string, PsychologyEnrichedTrade[]>()
  for (const row of enriched) {
    const emotion = normalizedEmotion(row.trade.emotion)
    if (!emotion) continue
    const list = byEmotion.get(emotion) ?? []
    list.push(row)
    byEmotion.set(emotion, list)
  }
  const emotionSides = [...byEmotion.entries()]
    .map(([emotion, rows]) => ({ emotion, rows, metrics: psychologyTradeMetrics(rows.map((row) => row.trade)) }))
    .filter((row) => row.metrics.tradeCount >= PSYCHOLOGY_ADVANCED_MIN_TRADES)
    .sort((a, b) => {
      const aPnl = a.metrics.averagePnL
      const bPnl = b.metrics.averagePnL
      if (aPnl == null && bPnl == null) {
        return (b.metrics.winRate ?? 0) - (a.metrics.winRate ?? 0)
      }
      if (aPnl == null) return 1
      if (bPnl == null) return -1
      if (aPnl !== bPnl) return bPnl - aPnl
      return (b.metrics.winRate ?? 0) - (a.metrics.winRate ?? 0)
    })
  if (emotionSides.length >= 2) {
    const best = emotionSides[0]!
    const worst = emotionSides[emotionSides.length - 1]!
    const worseIsStrained = STRAINED_EMOTIONS.has(worst.emotion)
    const suggestionWhenBestLeads = worseIsStrained
      ? `Noticing ${worst.emotion} before you enter may be a useful pause.`
      : "That tag has not lined up with weaker results here."
    drafts.push({
      id: "emotion",
      category: "emotion",
      title: "Emotion",
      left: sideFrom(best.emotion, best.emotion, best.rows),
      right: sideFrom(worst.emotion, worst.emotion, worst.rows),
      favorable: "left",
      rank: 35,
      whenLeftLeads: {
        pnl: {
          headline: `Trades tagged ${best.emotion} have performed better than trades tagged ${worst.emotion}.`,
          suggestion: suggestionWhenBestLeads,
        },
        winRate: {
          headline: `Trades tagged ${best.emotion} have won more often than trades tagged ${worst.emotion}.`,
          suggestion: suggestionWhenBestLeads,
        },
      },
      whenRightLeads: {
        pnl: {
          headline: `Trades tagged ${worst.emotion} have performed better than trades tagged ${best.emotion} in this sample.`,
          suggestion: "The tag alone is not pointing to a weakness right now.",
        },
        winRate: {
          headline: `Trades tagged ${worst.emotion} have won more often than trades tagged ${best.emotion} in this sample.`,
          suggestion: "The tag alone is not pointing to a weakness right now.",
        },
      },
    })
  }

  const pauses = enriched
    .map((row) => rulesFor(row).consecutiveLossPause)
    .filter((value): value is number => value != null)
  const personalPause = pauses.length > 0
  const uniquePause = new Set(pauses).size === 1 ? pauses[0]! : null
  const baseline = personalPause
    ? enriched.filter(
        (row) =>
          rulesFor(row).consecutiveLossPause != null && row.consecutiveLossesBefore === 0
      )
    : enriched.filter((row) => row.consecutiveLossesBefore === 0)
  const afterStreak = personalPause
    ? enriched.filter((row) => {
        const pause = rulesFor(row).consecutiveLossPause
        return pause != null && row.consecutiveLossesBefore >= pause
      })
    : enriched.filter((row) => row.consecutiveLossesBefore >= 2)
  const afterLabel =
    personalPause && uniquePause != null
      ? `After ${uniquePause}+ losses`
      : personalPause
        ? "After your pause"
        : "After 2+ losses"
  drafts.push({
    id: "afterLosses",
    category: "afterLosses",
    title: "After losses",
    left: sideFrom("No prior loss", "baseline", baseline),
    right: sideFrom(afterLabel, "post-streak", afterStreak),
    favorable: "left",
    rank: 8,
    whenLeftLeads: {
      pnl: {
        headline: personalPause
          ? "Trades taken after your consecutive-loss pause have tended to perform worse."
          : "Trades taken after a losing streak have tended to perform worse.",
        suggestion: personalPause
          ? "That is a result difference after your saved pause. It does not explain why the trade was taken."
          : "Taking a break after consecutive losses may help.",
      },
      winRate: {
        headline: personalPause
          ? "Trades taken after your consecutive-loss pause have won less often."
          : "Trades taken after a losing streak have won less often.",
        suggestion: personalPause
          ? "That is a result difference after your saved pause. It does not explain why the trade was taken."
          : "Taking a break after consecutive losses may help.",
      },
    },
    whenRightLeads: {
      pnl: {
        headline: personalPause
          ? "Trades after your consecutive-loss pause have held up in this sample."
          : "Trades after a losing streak have held up in this sample.",
        suggestion: "A forced pause is not supported by these results.",
      },
      winRate: {
        headline: personalPause
          ? "Trades after your consecutive-loss pause have won more often in this sample."
          : "Trades after a losing streak have won more often in this sample.",
        suggestion: "A forced pause is not supported by these results.",
      },
    },
  })

  const caps = enriched
    .map((row) => rulesFor(row).maxTradesPerDay)
    .filter((value): value is number => value != null)
  const personalCap = caps.length > 0
  const uniqueCap = new Set(caps).size === 1 ? caps[0]! : null
  const early = personalCap
    ? enriched.filter((row) => {
        const cap = rulesFor(row).maxTradesPerDay
        return cap != null && row.tradeNumberInDay <= cap
      })
    : enriched.filter((row) => row.tradeNumberInDay >= 1 && row.tradeNumberInDay <= 3)
  const late = personalCap
    ? enriched.filter((row) => {
        const cap = rulesFor(row).maxTradesPerDay
        return cap != null && row.tradeNumberInDay > cap
      })
    : enriched.filter((row) => row.tradeNumberInDay >= 5)
  drafts.push({
    id: "tradeFrequency",
    category: "tradeFrequency",
    title: "Trade sequence",
    left: sideFrom(
      personalCap ? (uniqueCap != null ? `Within ${uniqueCap} trades` : "Within your daily cap") : "Trades 1–3",
      "earlier",
      early
    ),
    right: sideFrom(
      personalCap ? (uniqueCap != null ? `Beyond ${uniqueCap} trades` : "Beyond your daily cap") : "Trade 5+",
      "later",
      late
    ),
    favorable: "left",
    rank: 18,
    whenLeftLeads: {
      pnl: {
        headline: personalCap
          ? "Trades beyond your daily cap have performed worse than trades within it."
          : "Your earlier trades in the day have performed better than later ones.",
        suggestion: personalCap
          ? "This is your saved trade cap, not a guess about why the extra trades were taken."
          : "Reviewing whether later setups are lower quality may help.",
      },
      winRate: {
        headline: personalCap
          ? "Trades beyond your daily cap have won less often than trades within it."
          : "Your earlier trades in the day have won more often than later ones.",
        suggestion: personalCap
          ? "This is your saved trade cap, not a guess about why the extra trades were taken."
          : "Reviewing whether later setups are lower quality may help.",
      },
    },
    whenRightLeads: {
      pnl: {
        headline: personalCap
          ? "Trades beyond your daily cap have performed better than trades within it in this sample."
          : "Later trades in the day have performed better than your first few.",
        suggestion: personalCap
          ? "The cap is not pointing to weaker results right now."
          : "The open has not been your strongest window in this sample.",
      },
      winRate: {
        headline: personalCap
          ? "Trades beyond your daily cap have won more often than trades within it in this sample."
          : "Later trades in the day have won more often than your first few.",
        suggestion: personalCap
          ? "The cap is not pointing to weaker results right now."
          : "The open has not been your strongest window in this sample.",
      },
    },
  })

  const waits = enriched.some((row) => rulesFor(row).waitAfterLossMinutes != null)
  if (waits) {
    const rushed: PsychologyEnrichedTrade[] = []
    const waited: PsychologyEnrichedTrade[] = []
    for (let index = 1; index < enriched.length; index += 1) {
      const row = enriched[index]!
      const wait = rulesFor(row).waitAfterLossMinutes
      if (wait == null || !row.previousTradeWasLoss) continue
      const minutes = (row.trade.entryAtMs - enriched[index - 1]!.trade.entryAtMs) / 60000
      if (!Number.isFinite(minutes) || minutes < 0) continue
      if (minutes < wait) rushed.push(row)
      else waited.push(row)
    }
    drafts.push({
      id: "afterLossesWait",
      category: "afterLosses",
      title: "Wait after a loss",
      left: sideFrom("Waited", "waited", waited),
      right: sideFrom("Before the wait", "rushed", rushed),
      favorable: "left",
      rank: 9,
      whenLeftLeads: {
        pnl: {
          headline: "Trades taken before your waiting time after a loss have performed worse than trades that waited.",
          suggestion: "This compares results against your saved wait. It does not label those trades.",
        },
        winRate: {
          headline: "Trades taken before your waiting time after a loss have won less often than trades that waited.",
          suggestion: "This compares results against your saved wait. It does not label those trades.",
        },
      },
      whenRightLeads: {
        pnl: {
          headline: "Trades taken before your waiting time have held up in this sample.",
          suggestion: "The saved wait is not pointing to weaker results right now.",
        },
        winRate: {
          headline: "Trades taken before your waiting time have won more often in this sample.",
          suggestion: "The saved wait is not pointing to weaker results right now.",
        },
      },
    })
  }

  return drafts.flatMap((draft) => {
    const resolved = consider(draft)
    return resolved ? [resolved] : []
  })
}

function toCard(comparison: ResolvedPsychologyComparison): PsychologyInsightCard {
  const minCount = Math.min(
    comparison.left.metrics.tradeCount,
    comparison.right.metrics.tradeCount
  )
  return {
    id: comparison.id,
    category: comparison.category,
    sectionTitle: comparison.title,
    headline: comparison.headline,
    detail: `${comparison.suggestion} ${comparison.sampleLine}`,
    sampleSize: comparison.left.metrics.tradeCount + comparison.right.metrics.tradeCount,
    reliability: reliabilityFor(minCount),
    rankingScore:
      comparison.gap.winRateGap * 100 +
      (comparison.gap.averagePnLGap ?? 0) / 50 +
      (100 - comparison.rank) / 1000,
  }
}

export function buildInterpretivePsychologyInsights(
  enriched: readonly PsychologyEnrichedTrade[],
  preferences: PreferenceRuleContext | null = null
): PsychologyInsightCard[] {
  return collectComparisons(enriched, (row) => psychologyRulesAt(preferences, row.trade.entryAtMs))
    .filter(
      (comparison) =>
        Math.min(comparison.left.metrics.tradeCount, comparison.right.metrics.tradeCount) >=
        PSYCHOLOGY_INSIGHT_MIN_TRADES
    )
    .sort((a, b) => toCard(b).rankingScore - toCard(a).rankingScore)
    .slice(0, PSYCHOLOGY_INSIGHT_LIMIT)
    .map(toCard)
}

export function buildPsychologyAdvancedSections(
  enriched: readonly PsychologyEnrichedTrade[],
  preferences: PreferenceRuleContext | null = null
): PsychologyAnalyticsSection[] {
  return collectComparisons(enriched, (row) => psychologyRulesAt(preferences, row.trade.entryAtMs))
    .sort((a, b) => a.rank - b.rank)
    .map((comparison) => {
      const leader = comparison.leader === "left" ? comparison.left : comparison.right
      return {
        id: comparison.id,
        title: comparison.title,
        subtitle: null,
        groups: [
          {
            id: `${comparison.id}.left`,
            label: comparison.left.label,
            metrics: comparison.left.metrics,
            highlight: leader === comparison.left,
          },
          {
            id: `${comparison.id}.right`,
            label: comparison.right.label,
            metrics: comparison.right.metrics,
            highlight: leader === comparison.right,
          },
        ],
        footnote: comparison.sampleLine,
      }
    })
}

function findComparison(
  comparisons: readonly ResolvedPsychologyComparison[],
  id: string
): ResolvedPsychologyComparison | undefined {
  return comparisons.find(
    (comparison) =>
      comparison.id === id &&
      Math.min(comparison.left.metrics.tradeCount, comparison.right.metrics.tradeCount) >=
        PSYCHOLOGY_INSIGHT_MIN_TRADES
  )
}

export function derivePsychologyGuardrails(
  enriched: readonly PsychologyEnrichedTrade[],
  preferences: PreferenceRuleContext | null = null
): PsychologyCoachGuardrailFacts {
  const rulesFor = (row: PsychologyEnrichedTrade) =>
    psychologyRulesAt(preferences, row.trade.entryAtMs)
  const comparisons = collectComparisons(enriched, rulesFor)
  const current = currentPsychologyRules(preferences)
  const personalPause = enriched.some((row) => rulesFor(row).consecutiveLossPause != null)
  const personalCap = enriched.some((row) => rulesFor(row).maxTradesPerDay != null)
  const sleep = findComparison(comparisons, "sleep")
  const stress = findComparison(comparisons, "stress")
  const focus = findComparison(comparisons, "focus")
  const losses = findComparison(comparisons, "afterLosses")
  const frequency = findComparison(comparisons, "tradeFrequency")

  const shortSleepWeaker = sleep != null && sleep.leader === "left"
  const lowStressBetter = stress != null && stress.leader === "left"
  const highFocusBetter = focus != null && focus.leader === "left"
  const streakWeaker = losses != null && losses.leader === "left"
  const earlyBetter = frequency != null && frequency.leader === "left"

  return {
    consecutiveLossCheckpoint: streakWeaker
      ? (current.consecutiveLossPause ?? (personalPause ? null : 2))
      : null,
    consecutiveLossWinRateAfter: losses?.right.metrics.winRate ?? null,
    consecutiveLossBaselineWinRate: losses?.left.metrics.winRate ?? null,
    lowSleepHoursThreshold: shortSleepWeaker ? 6 : null,
    lowSleepExpectancy: shortSleepWeaker ? (sleep?.right.metrics.averagePnL ?? null) : null,
    maxTradesDaySoftLimit: earlyBetter
      ? (current.maxTradesPerDay ?? (personalCap ? null : 4))
      : null,
    lateTradeAveragePnL: frequency?.right.metrics.averagePnL ?? null,
    earlyTradeAveragePnL: frequency?.left.metrics.averagePnL ?? null,
    highStressWeaker: lowStressBetter,
    lowFocusWeaker: highFocusBetter,
    personalLossPause: current.consecutiveLossPause != null,
    personalTradeCap: current.maxTradesPerDay != null,
  }
}

export function countMatchedPsychologyDays(
  trades: readonly PsychologyReportTrade[],
  checkIns: readonly TraderDailyCheckIn[]
): number {
  const complete = checkIns.filter(isCompleteCheckIn)
  const byDate = new Set(complete.map((checkIn) => checkIn.checkInDate))
  const matched = new Set<string>()
  for (const trade of trades) {
    const key = psychologyTradeDateKey(trade)
    if (!key || !byDate.has(key)) continue
    matched.add(key)
  }
  return matched.size
}
