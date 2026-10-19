import { isElevatedStress } from "../../dailyCheckIn/types.ts"
import { TRADE_REVIEW_EMOTIONS } from "./catalog.ts"
import {
  resolveLossBucket,
  resolveSequenceBucket,
  resolveSleepBand,
  SLEEP_BANDS,
} from "./enrich.ts"
import {
  psychologyTradeMetrics,
  qualifiesForComparison,
  qualifiesForDashboardCard,
} from "./metrics.ts"
import { formatPsychologyMoney, formatPsychologyWinRate } from "./format.ts"
import type {
  PsychologyEnrichedTrade,
  PsychologyGroupMetrics,
  PsychologyInsightCard,
  PsychologyInsightCategory,
} from "./types.ts"

function makeCard(input: {
  id: string
  category: PsychologyInsightCategory
  sectionTitle: string
  headline: string
  detail: string
  metrics: PsychologyGroupMetrics
  magnitude: number
  actionability: number
}): PsychologyInsightCard {
  const reliabilityWeight =
    input.metrics.reliability === "insufficient"
      ? 0
      : input.metrics.reliability === "earlySignal"
        ? 0.35
        : input.metrics.reliability === "developing"
          ? 0.75
          : 1
  const sampleWeight = Math.min(1, input.metrics.tradeCount / 30)
  const magnitudeWeight = Math.min(1, input.magnitude / 50)
  return {
    id: input.id,
    category: input.category,
    sectionTitle: input.sectionTitle,
    headline: input.headline,
    detail: input.detail,
    sampleSize: input.metrics.tradeCount,
    reliability: input.metrics.reliability,
    rankingScore: reliabilityWeight * sampleWeight * magnitudeWeight * input.actionability,
  }
}

function expectancyOf(metrics: PsychologyGroupMetrics): number {
  return metrics.expectancy ?? metrics.averagePnL ?? 0
}

function normalizedEmotion(raw: string | null): string | null {
  const trimmed = String(raw ?? "").trim()
  if (!trimmed) return null
  return (
    TRADE_REVIEW_EMOTIONS.find(
      (emotion) => emotion.toLowerCase() === trimmed.toLowerCase()
    ) ?? trimmed
  )
}

function sleepInsights(
  enriched: PsychologyEnrichedTrade[]
): PsychologyInsightCard[] {
  const withSleep = enriched.filter((item) => item.dailyCheckIn?.sleepHours != null)
  if (withSleep.length === 0) return []

  const grouped = new Map<string, PsychologyEnrichedTrade[]>()
  for (const item of withSleep) {
    const band = resolveSleepBand(item.dailyCheckIn?.sleepHours) ?? "<5h"
    const rows = grouped.get(band) ?? []
    rows.push(item)
    grouped.set(band, rows)
  }

  const metricsByBand = SLEEP_BANDS.flatMap((band) => {
    const items = grouped.get(band)
    if (!items?.length) return []
    const metrics = psychologyTradeMetrics(items.map((row) => row.trade))
    if (!qualifiesForDashboardCard(metrics.reliability)) return []
    return [{ band, metrics }]
  })
  if (metricsByBand.length < 2) return []

  const best = metricsByBand.reduce((lead, row) =>
    expectancyOf(row.metrics) > expectancyOf(lead.metrics) ? row : lead
  )
  const worst = metricsByBand.reduce((lead, row) =>
    expectancyOf(row.metrics) < expectancyOf(lead.metrics) ? row : lead
  )
  if (best.band === worst.band) return []

  const delta = Math.abs(expectancyOf(best.metrics) - expectancyOf(worst.metrics))
  if (delta < 5 && !qualifiesForComparison(best.metrics.reliability)) return []

  const detail =
    qualifiesForComparison(best.metrics.reliability) &&
    qualifiesForComparison(worst.metrics.reliability)
      ? `Your data shows ${formatPsychologyMoney(expectancyOf(best.metrics))} expectancy at ${best.band} versus ${formatPsychologyMoney(expectancyOf(worst.metrics))} at ${worst.band} • ${best.metrics.tradeCount} trades`
      : `${formatPsychologyMoney(expectancyOf(best.metrics))} expectancy • ${best.metrics.tradeCount} trades • ${best.metrics.reliability === "earlySignal" ? "Early signal" : best.metrics.reliability}`

  return [
    makeCard({
      id: "sleep.best",
      category: "sleep",
      sectionTitle: "Sleep",
      headline: `Best performance at ${best.band}`,
      detail,
      metrics: best.metrics,
      magnitude: delta,
      actionability: 0.9,
    }),
  ]
}

type RatingDimension = {
  key: "sleepQuality" | "morningRating" | "stress" | "energy" | "focus"
  title: string
  higherIsBetter: boolean
  read: (item: PsychologyEnrichedTrade) => number | null
}

const RATING_DIMENSIONS: RatingDimension[] = [
  {
    key: "sleepQuality",
    title: "Sleep Quality",
    higherIsBetter: true,
    read: (item) => item.dailyCheckIn?.sleepQuality ?? null,
  },
  {
    key: "morningRating",
    title: "Morning",
    higherIsBetter: true,
    read: (item) => item.dailyCheckIn?.morningRating ?? null,
  },
  {
    key: "stress",
    title: "Stress",
    higherIsBetter: false,
    read: (item) => item.dailyCheckIn?.stressLevel ?? null,
  },
  {
    key: "energy",
    title: "Energy",
    higherIsBetter: true,
    read: (item) => item.dailyCheckIn?.energyLevel ?? null,
  },
  {
    key: "focus",
    title: "Focus",
    higherIsBetter: true,
    read: (item) => item.dailyCheckIn?.focusLevel ?? null,
  },
]

function groupedRatingInsight(
  dimension: RatingDimension,
  withRating: Array<{ item: PsychologyEnrichedTrade; rating: number }>
): PsychologyInsightCard | null {
  const grouped = new Map<string, PsychologyEnrichedTrade[]>()
  for (const row of withRating) {
    const band = row.rating <= 2 ? "1–2" : row.rating === 3 ? "3" : "4–5"
    const list = grouped.get(band) ?? []
    list.push(row.item)
    grouped.set(band, list)
  }
  const bandMetrics = (["1–2", "3", "4–5"] as const).flatMap((band) => {
    const rows = grouped.get(band)
    if (!rows) return []
    const metrics = psychologyTradeMetrics(rows.map((row) => row.trade))
    if (!qualifiesForDashboardCard(metrics.reliability)) return []
    return [{ band, metrics }]
  })
  if (bandMetrics.length < 2) return null

  const scored = [...bandMetrics].sort(
    (a, b) => (a.metrics.expectancy ?? 0) - (b.metrics.expectancy ?? 0)
  )
  const best = dimension.higherIsBetter ? scored[scored.length - 1] : scored[0]
  const worst = dimension.higherIsBetter ? scored[0] : scored[scored.length - 1]
  const delta = Math.abs((best.metrics.expectancy ?? 0) - (worst.metrics.expectancy ?? 0))
  if (delta < 5) return null

  return makeCard({
    id: `rating.group.${dimension.key}`,
    category: "mentalState",
    sectionTitle: dimension.title,
    headline: `${dimension.title} ${best.band} band leads your sample`,
    detail: `${formatPsychologyMoney(expectancyOf(best.metrics))} expectancy (${best.metrics.tradeCount} trades) vs ${formatPsychologyMoney(expectancyOf(worst.metrics))} (${worst.metrics.tradeCount} trades)`,
    metrics: best.metrics,
    magnitude: delta,
    actionability: 0.7,
  })
}

function ratingInsight(dimension: RatingDimension, enriched: PsychologyEnrichedTrade[]): PsychologyInsightCard | null {
  const withRating = enriched.flatMap((item) => {
    const rating = dimension.read(item)
    return rating == null ? [] : [{ item, rating }]
  })
  if (withRating.length === 0) return null

  const byRating = new Map<number, PsychologyEnrichedTrade[]>()
  for (const row of withRating) {
    const list = byRating.get(row.rating) ?? []
    list.push(row.item)
    byRating.set(row.rating, list)
  }
  const ratingMetrics = [1, 2, 3, 4, 5].flatMap((rating) => {
    const rows = byRating.get(rating)
    if (!rows) return []
    const metrics = psychologyTradeMetrics(rows.map((row) => row.trade))
    if (!qualifiesForDashboardCard(metrics.reliability)) return []
    return [{ rating, metrics }]
  })
  if (ratingMetrics.length < 2) {
    return groupedRatingInsight(dimension, withRating)
  }

  const sorted = [...ratingMetrics].sort((a, b) =>
    dimension.higherIsBetter ? b.rating - a.rating : a.rating - b.rating
  )
  const best = sorted[0]
  const worst = sorted[sorted.length - 1]
  if (best.rating === worst.rating) return null
  const delta = Math.abs(expectancyOf(best.metrics) - expectancyOf(worst.metrics))
  if (delta < 5) return null

  return makeCard({
    id: `rating.${dimension.key}`,
    category: "mentalState",
    sectionTitle: dimension.title,
    headline:
      dimension.key === "stress"
        ? "Lower stress associated with better results"
        : `Higher ${dimension.title.toLowerCase()} associated with better results`,
    detail: `Rating ${best.rating}/5 (${formatPsychologyWinRate(best.metrics.winRate)} win rate) vs ${worst.rating}/5 (${formatPsychologyWinRate(worst.metrics.winRate)}) • ${best.metrics.tradeCount} vs ${worst.metrics.tradeCount} trades`,
    metrics: best.metrics,
    magnitude: delta,
    actionability: dimension.key === "stress" || dimension.key === "focus" ? 0.85 : 0.75,
  })
}

function convictionInsights(enriched: PsychologyEnrichedTrade[]): PsychologyInsightCard[] {
  const withConviction = enriched.flatMap((item) => {
    const confidence = item.trade.confidence
    return confidence != null && confidence >= 1 && confidence <= 5
      ? [{ item, confidence }]
      : []
  })
  if (withConviction.length === 0) return []
  const low = withConviction.filter((row) => row.confidence <= 2)
  const high = withConviction.filter((row) => row.confidence >= 4)
  const lowMetrics = psychologyTradeMetrics(low.map((row) => row.item.trade))
  const highMetrics = psychologyTradeMetrics(high.map((row) => row.item.trade))
  if (
    !qualifiesForDashboardCard(lowMetrics.reliability) ||
    !qualifiesForDashboardCard(highMetrics.reliability)
  ) {
    return []
  }
  const delta = Math.abs((highMetrics.expectancy ?? 0) - (lowMetrics.expectancy ?? 0))
  return [
    makeCard({
      id: "conviction.highVsLow",
      category: "conviction",
      sectionTitle: "Conviction",
      headline:
        (highMetrics.expectancy ?? 0) >= (lowMetrics.expectancy ?? 0)
          ? "High-conviction trades outperform"
          : "Lower conviction trades outperform in your sample",
      detail: `Conviction 4–5: ${formatPsychologyWinRate(highMetrics.winRate)} win rate (${highMetrics.tradeCount} trades) vs 1–2: ${formatPsychologyWinRate(lowMetrics.winRate)} (${lowMetrics.tradeCount} trades)`,
      metrics: highMetrics,
      magnitude: Math.max(delta, 1),
      actionability: 0.8,
    }),
  ]
}

function followedPlanInsights(enriched: PsychologyEnrichedTrade[]): PsychologyInsightCard[] {
  const followed = enriched.filter((item) => item.trade.followedPlan === true)
  const notFollowed = enriched.filter((item) => item.trade.followedPlan === false)
  if (!followed.length || !notFollowed.length) return []
  const followedMetrics = psychologyTradeMetrics(followed.map((row) => row.trade))
  const brokenMetrics = psychologyTradeMetrics(notFollowed.map((row) => row.trade))
  if (
    !qualifiesForDashboardCard(followedMetrics.reliability) ||
    !qualifiesForDashboardCard(brokenMetrics.reliability)
  ) {
    return []
  }
  const delta = Math.abs((followedMetrics.averagePnL ?? 0) - (brokenMetrics.averagePnL ?? 0))
  if (delta < 5) return []
  return [
    makeCard({
      id: "discipline.followedPlan",
      category: "discipline",
      sectionTitle: "Discipline",
      headline: "Following your plan matters",
      detail: `Plan followed: ${formatPsychologyMoney(followedMetrics.averagePnL ?? 0)} avg (${followedMetrics.tradeCount} trades) vs not followed: ${formatPsychologyMoney(brokenMetrics.averagePnL ?? 0)} (${brokenMetrics.tradeCount} trades)`,
      metrics: followedMetrics,
      magnitude: delta,
      actionability: 0.95,
    }),
  ]
}

function emotionInsights(enriched: PsychologyEnrichedTrade[]): PsychologyInsightCard[] {
  const normalized = enriched.flatMap((item) => {
    const emotion = normalizedEmotion(item.trade.emotion)
    return emotion ? [{ item, emotion }] : []
  })
  const grouped = new Map<string, PsychologyEnrichedTrade[]>()
  for (const row of normalized) {
    const list = grouped.get(row.emotion) ?? []
    list.push(row.item)
    grouped.set(row.emotion, list)
  }
  const emotionMetrics = TRADE_REVIEW_EMOTIONS.flatMap((emotion) => {
    const rows = grouped.get(emotion)
    if (!rows) return []
    const metrics = psychologyTradeMetrics(rows.map((row) => row.trade))
    if (!qualifiesForDashboardCard(metrics.reliability)) return []
    return [{ emotion, metrics }]
  })
  if (emotionMetrics.length < 2) return []
  const worst = emotionMetrics.reduce((lead, row) =>
    expectancyOf(row.metrics) < expectancyOf(lead.metrics) ? row : lead
  )
  const best = emotionMetrics.reduce((lead, row) =>
    expectancyOf(row.metrics) > expectancyOf(lead.metrics) ? row : lead
  )
  if (worst.emotion === best.emotion) return []
  const delta = Math.abs(expectancyOf(best.metrics) - expectancyOf(worst.metrics))
  if (delta < 5) return []
  return [
    makeCard({
      id: `emotion.${worst.emotion.toLowerCase()}`,
      category: "emotion",
      sectionTitle: "Emotion",
      headline: `${worst.emotion} entries show your weakest expectancy`,
      detail: `${worst.emotion}: ${formatPsychologyMoney(expectancyOf(worst.metrics))} expectancy • ${worst.metrics.tradeCount} trades`,
      metrics: worst.metrics,
      magnitude: delta,
      actionability: 0.75,
    }),
  ]
}

function consecutiveLossInsights(enriched: PsychologyEnrichedTrade[]): PsychologyInsightCard[] {
  const grouped = new Map<string, PsychologyEnrichedTrade[]>()
  for (const item of enriched) {
    const bucket = resolveLossBucket(item.consecutiveLossesBefore)
    const list = grouped.get(bucket) ?? []
    list.push(item)
    grouped.set(bucket, list)
  }
  const baselineBucket = grouped.get("0 prior losses") ?? []
  if (baselineBucket.length < 5) return []
  const stressed = [
    ...(grouped.get("2 prior losses") ?? []),
    ...(grouped.get("3+ prior losses") ?? []),
  ]
  if (stressed.length < 5) return []
  const baselineMetrics = psychologyTradeMetrics(baselineBucket.map((row) => row.trade))
  const stressedMetrics = psychologyTradeMetrics(stressed.map((row) => row.trade))
  if (!qualifiesForDashboardCard(stressedMetrics.reliability)) return []
  const baseWR = baselineMetrics.winRate ?? 0
  const stressedWR = stressedMetrics.winRate ?? 0
  const delta = Math.abs(baseWR - stressedWR)
  const weaker = stressedWR < baseWR - 0.05
  return [
    makeCard({
      id: "afterLosses.streak",
      category: "afterLosses",
      sectionTitle: "After Losses",
      headline: weaker
        ? "Performance drops after multiple losses"
        : "Your performance stays stable after losses",
      detail: `${formatPsychologyWinRate(stressedWR)} win rate after 2+ losses vs ${formatPsychologyWinRate(baseWR)} baseline • ${stressedMetrics.tradeCount} trades`,
      metrics: stressedMetrics,
      magnitude: Math.max(delta * 100, 1),
      actionability: 0.9,
    }),
  ]
}

function tradeFrequencyInsights(enriched: PsychologyEnrichedTrade[]): PsychologyInsightCard[] {
  const grouped = new Map<string, PsychologyEnrichedTrade[]>()
  for (const item of enriched) {
    const bucket = resolveSequenceBucket(item.tradeNumberInDay)
    const list = grouped.get(bucket) ?? []
    list.push(item)
    grouped.set(bucket, list)
  }
  const early = [
    ...(grouped.get("Trade #1") ?? []),
    ...(grouped.get("Trade #2") ?? []),
    ...(grouped.get("Trade #3") ?? []),
  ]
  const late = grouped.get("Trade #5+") ?? []
  if (early.length < 5 || late.length < 5) return []
  const earlyMetrics = psychologyTradeMetrics(early.map((row) => row.trade))
  const lateMetrics = psychologyTradeMetrics(late.map((row) => row.trade))
  if (
    !qualifiesForDashboardCard(earlyMetrics.reliability) ||
    !qualifiesForDashboardCard(lateMetrics.reliability)
  ) {
    return []
  }
  const delta = Math.abs((earlyMetrics.averagePnL ?? 0) - (lateMetrics.averagePnL ?? 0))
  if (delta < 5) return []
  return [
    makeCard({
      id: "frequency.earlyVsLate",
      category: "tradeFrequency",
      sectionTitle: "Trade Frequency",
      headline:
        (earlyMetrics.averagePnL ?? 0) >= (lateMetrics.averagePnL ?? 0)
          ? "Early-day trades outperform later ones"
          : "Later trades outperform your openers",
      detail: `Trades 1–3 avg ${formatPsychologyMoney(earlyMetrics.averagePnL ?? 0)} (${earlyMetrics.tradeCount} trades) vs trade #5+ avg ${formatPsychologyMoney(lateMetrics.averagePnL ?? 0)} (${lateMetrics.tradeCount} trades)`,
      metrics: earlyMetrics,
      magnitude: delta,
      actionability: 0.85,
    }),
  ]
}

function combinedInsights(enriched: PsychologyEnrichedTrade[]): PsychologyInsightCard[] {
  const cards: PsychologyInsightCard[] = []
  const lowSleepHighStress = enriched.filter((item) => {
    const hours = item.dailyCheckIn?.sleepHours
    const stress = item.dailyCheckIn?.stressLevel
    return hours != null && hours < 6 && stress != null && isElevatedStress(stress)
  })
  if (lowSleepHighStress.length >= 10) {
    const combined = psychologyTradeMetrics(lowSleepHighStress.map((row) => row.trade))
    const lowSleepOnly = enriched.filter((item) => {
      const hours = item.dailyCheckIn?.sleepHours
      return hours != null && hours < 6
    })
    const comparison = psychologyTradeMetrics(lowSleepOnly.map((row) => row.trade))
    if (
      qualifiesForComparison(combined.reliability) &&
      qualifiesForComparison(comparison.reliability)
    ) {
      const delta = Math.abs((combined.expectancy ?? 0) - (comparison.expectancy ?? 0))
      if (delta >= 10) {
        cards.push(
          makeCard({
            id: "combined.sleepStress",
            category: "combined",
            sectionTitle: "Combined",
            headline: "Low sleep + high stress associated with weaker results",
            detail: `${formatPsychologyMoney(expectancyOf(combined))} expectancy (${combined.tradeCount} trades) when both are present`,
            metrics: combined,
            magnitude: delta,
            actionability: 0.65,
          })
        )
      }
    }
  }

  const disciplinedHighConviction = enriched.filter(
    (item) => (item.trade.confidence ?? 0) >= 4 && item.trade.followedPlan === true
  )
  if (disciplinedHighConviction.length >= 10) {
    const combined = psychologyTradeMetrics(
      disciplinedHighConviction.map((row) => row.trade)
    )
    const allHigh = psychologyTradeMetrics(
      enriched.filter((item) => (item.trade.confidence ?? 0) >= 4).map((row) => row.trade)
    )
    if (
      qualifiesForComparison(combined.reliability) &&
      qualifiesForComparison(allHigh.reliability) &&
      (combined.expectancy ?? 0) > (allHigh.expectancy ?? 0) + 5
    ) {
      cards.push(
        makeCard({
          id: "combined.convictionPlan",
          category: "combined",
          sectionTitle: "Combined",
          headline: "High conviction + plan followed is your strongest combo",
          detail: `${formatPsychologyMoney(expectancyOf(combined))} expectancy • ${combined.tradeCount} trades`,
          metrics: combined,
          magnitude: 10,
          actionability: 0.7,
        })
      )
    }
  }
  return cards
}

export function buildPsychologyInsightCards(
  enriched: PsychologyEnrichedTrade[]
): PsychologyInsightCard[] {
  return [
    ...sleepInsights(enriched),
    ...RATING_DIMENSIONS.flatMap((dimension) => {
      const card = ratingInsight(dimension, enriched)
      return card ? [card] : []
    }),
    ...convictionInsights(enriched),
    ...followedPlanInsights(enriched),
    ...emotionInsights(enriched),
    ...consecutiveLossInsights(enriched),
    ...tradeFrequencyInsights(enriched),
    ...combinedInsights(enriched),
  ]
    .filter((card) => qualifiesForDashboardCard(card.reliability))
    .sort((a, b) => b.rankingScore - a.rankingScore)
}

export { normalizedEmotion }
