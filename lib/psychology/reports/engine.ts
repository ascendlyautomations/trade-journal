import type { TraderDailyCheckIn } from "../../dailyCheckIn/types.ts"
import { TRADE_REVIEW_EMOTIONS } from "./catalog.ts"
import {
  enrichPsychologyTrades,
  resolveLossBucket,
  resolveSequenceBucket,
  resolveSleepBand,
  SLEEP_BANDS,
} from "./enrich.ts"
import { buildPsychologyInsightCards, normalizedEmotion } from "./insights.ts"
import { psychologyTradeMetrics } from "./metrics.ts"
import { reliabilityLabel } from "./metrics.ts"
import type {
  PsychologyAnalyticsGroupRow,
  PsychologyAnalyticsReport,
  PsychologyAnalyticsSection,
  PsychologyEnrichedTrade,
  PsychologyReportTrade,
} from "./types.ts"

function section(
  id: string,
  title: string,
  subtitle: string | null,
  rows: PsychologyAnalyticsGroupRow[],
  emptyMessage: string | null
): PsychologyAnalyticsSection {
  return {
    id,
    title,
    subtitle,
    groups: rows,
    footnote: rows.length === 0 ? emptyMessage : null,
  }
}

function buildAnalyticsSections(
  enriched: PsychologyEnrichedTrade[],
  cards: ReturnType<typeof buildPsychologyInsightCards>
): PsychologyAnalyticsSection[] {
  const baseline = psychologyTradeMetrics(enriched.map((row) => row.trade))
  const sections: PsychologyAnalyticsSection[] = [
    {
      id: "overview",
      title: "Overview",
      subtitle: `Based on ${baseline.tradeCount} trades in this period`,
      groups: [
        {
          id: "baseline",
          label: "All trades",
          metrics: baseline,
          highlight: false,
        },
      ],
      footnote: reliabilityLabel(baseline.reliability),
    },
  ]

  const withSleep = enriched.filter((item) => item.dailyCheckIn?.sleepHours != null)
  const sleepGrouped = new Map<string, PsychologyEnrichedTrade[]>()
  for (const item of withSleep) {
    const band = resolveSleepBand(item.dailyCheckIn?.sleepHours) ?? "<5h"
    const list = sleepGrouped.get(band) ?? []
    list.push(item)
    sleepGrouped.set(band, list)
  }
  sections.push(
    section(
      "sleep",
      "Sleep",
      "Trades with a daily check-in that logged sleep hours",
      SLEEP_BANDS.flatMap((band) => {
        const items = sleepGrouped.get(band)
        if (!items) return []
        return [
          {
            id: band,
            label: band,
            metrics: psychologyTradeMetrics(items.map((row) => row.trade)),
            highlight: false,
          },
        ]
      }),
      "Log daily check-ins with sleep hours to unlock sleep analysis."
    )
  )

  const mentalRows: PsychologyAnalyticsGroupRow[] = []
  const dimensions = [
    ["sleepQuality", "Sleep Quality"],
    ["morningRating", "Morning"],
    ["stress", "Stress"],
    ["energy", "Energy"],
    ["focus", "Focus"],
  ] as const
  for (const [key, title] of dimensions) {
    for (let rating = 1; rating <= 5; rating += 1) {
      const items = enriched.filter((item) => {
        const checkIn = item.dailyCheckIn
        if (!checkIn) return false
        const value =
          key === "sleepQuality"
            ? checkIn.sleepQuality
            : key === "morningRating"
              ? checkIn.morningRating
              : key === "stress"
                ? checkIn.stressLevel
                : key === "energy"
                  ? checkIn.energyLevel
                  : checkIn.focusLevel
        return value === rating
      })
      if (!items.length) continue
      mentalRows.push({
        id: `${key}.${rating}`,
        label: `${title} ${rating}/5`,
        metrics: psychologyTradeMetrics(items.map((row) => row.trade)),
        highlight: false,
      })
    }
  }
  sections.push(
    section(
      "mentalState",
      "Mental State",
      "Sleep quality, morning, stress, energy, and focus ratings",
      mentalRows,
      "Complete daily check-ins to analyze mental-state patterns."
    )
  )

  sections.push(
    section(
      "conviction",
      "Trade Psychology",
      "Conviction at entry",
      [1, 2, 3, 4, 5].flatMap((level) => {
        const items = enriched.filter((item) => item.trade.confidence === level)
        if (!items.length) return []
        return [
          {
            id: `conviction.${level}`,
            label: `Conviction ${level}/5`,
            metrics: psychologyTradeMetrics(items.map((row) => row.trade)),
            highlight: false,
          },
        ]
      }),
      "Add conviction on more trades to unlock this section."
    )
  )

  const followed = enriched.filter((item) => item.trade.followedPlan === true)
  const notFollowed = enriched.filter((item) => item.trade.followedPlan === false)
  const unknown = enriched.filter((item) => item.trade.followedPlan == null)
  const disciplineRows: PsychologyAnalyticsGroupRow[] = []
  if (followed.length) {
    disciplineRows.push({
      id: "plan.yes",
      label: "Followed plan",
      metrics: psychologyTradeMetrics(followed.map((row) => row.trade)),
      highlight: false,
    })
  }
  if (notFollowed.length) {
    disciplineRows.push({
      id: "plan.no",
      label: "Did not follow plan",
      metrics: psychologyTradeMetrics(notFollowed.map((row) => row.trade)),
      highlight: false,
    })
  }
  if (unknown.length) {
    disciplineRows.push({
      id: "plan.unknown",
      label: "Not recorded",
      metrics: psychologyTradeMetrics(unknown.map((row) => row.trade)),
      highlight: false,
    })
  }
  sections.push(
    section(
      "discipline",
      "Discipline",
      "Plan adherence",
      disciplineRows,
      "Mark plan adherence on trades to compare discipline."
    )
  )

  const emotionGrouped = new Map<string, PsychologyEnrichedTrade[]>()
  for (const item of enriched) {
    const emotion = normalizedEmotion(item.trade.emotion)
    if (!emotion) continue
    const list = emotionGrouped.get(emotion) ?? []
    list.push(item)
    emotionGrouped.set(emotion, list)
  }
  sections.push(
    section(
      "emotion",
      "Emotion",
      "Emotion before entry",
      TRADE_REVIEW_EMOTIONS.flatMap((emotion) => {
        const items = emotionGrouped.get(emotion)
        if (!items) return []
        return [
          {
            id: `emotion.${emotion}`,
            label: emotion,
            metrics: psychologyTradeMetrics(items.map((row) => row.trade)),
            highlight: false,
          },
        ]
      }),
      "Tag emotions on trades to analyze emotional patterns."
    )
  )

  const lossGrouped = new Map<string, PsychologyEnrichedTrade[]>()
  for (const item of enriched) {
    const bucket = resolveLossBucket(item.consecutiveLossesBefore)
    const list = lossGrouped.get(bucket) ?? []
    list.push(item)
    lossGrouped.set(bucket, list)
  }
  sections.push(
    section(
      "afterLosses",
      "After Losses",
      "Performance by consecutive losses before entry",
      (["0 prior losses", "1 prior loss", "2 prior losses", "3+ prior losses"] as const).flatMap(
        (bucket) => {
          const items = lossGrouped.get(bucket)
          if (!items) return []
          return [
            {
              id: bucket,
              label: bucket,
              metrics: psychologyTradeMetrics(items.map((row) => row.trade)),
              highlight: false,
            },
          ]
        }
      ),
      null
    )
  )

  const seqGrouped = new Map<string, PsychologyEnrichedTrade[]>()
  for (const item of enriched) {
    const bucket = resolveSequenceBucket(item.tradeNumberInDay)
    const list = seqGrouped.get(bucket) ?? []
    list.push(item)
    seqGrouped.set(bucket, list)
  }
  sections.push(
    section(
      "tradeFrequency",
      "Trade Frequency",
      "Trade sequence within each trading day",
      (["Trade #1", "Trade #2", "Trade #3", "Trade #4", "Trade #5+"] as const).flatMap(
        (bucket) => {
          const items = seqGrouped.get(bucket)
          if (!items) return []
          return [
            {
              id: bucket,
              label: bucket,
              metrics: psychologyTradeMetrics(items.map((row) => row.trade)),
              highlight: false,
            },
          ]
        }
      ),
      null
    )
  )

  const combined = cards.filter((card) => card.category === "combined")
  if (combined.length) {
    sections.push({
      id: "combined",
      title: "Combined Signals",
      subtitle: "Conservative multi-factor patterns only",
      groups: combined.map((card) => ({
        id: card.id,
        label: card.headline,
        metrics: {
          ...psychologyTradeMetrics([]),
          tradeCount: card.sampleSize,
          reliability: card.reliability,
        },
        highlight: true,
      })),
      footnote: "Associated patterns — not proof of causation.",
    })
  }

  return sections
}

export function buildPsychologyAnalyticsReport(
  trades: readonly PsychologyReportTrade[],
  checkIns: readonly TraderDailyCheckIn[],
  now: Date = new Date()
): PsychologyAnalyticsReport {
  const enriched = enrichPsychologyTrades(trades, checkIns)
  const baseline = psychologyTradeMetrics(enriched.map((row) => row.trade))
  const ranked = buildPsychologyInsightCards(enriched)
  return {
    generatedAt: now.getTime(),
    baseline,
    dashboardCards: ranked.slice(0, 5),
    sections: buildAnalyticsSections(enriched, ranked),
    enrichedTradeCount: enriched.length,
    checkInMatchedTradeCount: enriched.filter((row) => row.dailyCheckIn != null).length,
  }
}
