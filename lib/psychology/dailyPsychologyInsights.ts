import { formatPsychologyMoney, formatPsychologyWinRate } from "./reports/format.ts"
import type {
  PsychologyGroupMetrics,
  PsychologyInsightCard,
  PsychologyInsightCategory,
  PsychologySampleReliability,
} from "./reports/types.ts"
import { psychologyTradeMetrics } from "./reports/metrics.ts"
import type { MatchedTradingDay, TradeWithPnL } from "./matchedTradingDays.ts"
import { buildMatchedTradingDays } from "./matchedTradingDays.ts"

export { buildMatchedTradingDays } from "./matchedTradingDays.ts"
import { enrichPsychologyTrades } from "./reports/enrich.ts"
import type { PsychologyReportTrade } from "./reports/types.ts"
import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import { isCompleteCheckIn } from "../dailyCheckIn/validation.ts"

export type DailyGroupAggregate = {
  label: string
  days: MatchedTradingDay[]
  dayCount: number
  tradeCount: number
  totalPnL: number
  avgDailyPnL: number
  winRate: number | null
  reliability: PsychologySampleReliability
}

export function resolveMatchedDayReliability(
  dayCount: number,
  tradeCount: number
): PsychologySampleReliability {
  if (dayCount < 1 || tradeCount < 1) return "insufficient"
  if (dayCount === 1 && tradeCount < 5) return "earlySignal"
  if (dayCount <= 4) return "earlySignal"
  if (dayCount <= 9) return "developing"
  return "strong"
}

function aggregateDays(label: string, days: MatchedTradingDay[]): DailyGroupAggregate {
  const tradeCount = days.reduce((s, d) => s + d.tradeCount, 0)
  const winCount = days.reduce((s, d) => s + d.winCount, 0)
  const totalPnL = days.reduce((s, d) => s + d.dailyPnL, 0)
  const dayCount = days.length
  return {
    label,
    days,
    dayCount,
    tradeCount,
    totalPnL,
    avgDailyPnL: dayCount > 0 ? totalPnL / dayCount : 0,
    winRate: tradeCount > 0 ? winCount / tradeCount : null,
    reliability: resolveMatchedDayReliability(dayCount, tradeCount),
  }
}

function toGroupMetrics(group: DailyGroupAggregate): PsychologyGroupMetrics {
  const winCount = group.days.reduce((s, d) => s + d.winCount, 0)
  const lossCount = group.days.reduce((s, d) => s + d.lossCount, 0)
  return {
    tradeCount: group.tradeCount,
    winCount,
    lossCount,
    winRate: group.winRate,
    totalPnL: group.totalPnL,
    averagePnL: group.tradeCount > 0 ? group.totalPnL / group.tradeCount : null,
    expectancy: group.tradeCount > 0 ? group.totalPnL / group.tradeCount : null,
    averageRR: null,
    profitFactor: null,
    reliability: group.reliability,
  }
}

function reliabilityNote(reliability: PsychologySampleReliability): string {
  switch (reliability) {
    case "earlySignal":
      return "Early observation — small sample"
    case "developing":
      return "Developing pattern"
    case "strong":
      return "Stronger sample"
    default:
      return "Limited data"
  }
}

function makeDailyCard(input: {
  id: string
  category: PsychologyInsightCategory
  sectionTitle: string
  headline: string
  detail: string
  group: DailyGroupAggregate
  rankingScore: number
}): PsychologyInsightCard {
  const metrics = toGroupMetrics(input.group)
  return {
    id: input.id,
    category: input.category,
    sectionTitle: input.sectionTitle,
    headline: input.headline,
    detail: input.detail,
    sampleSize: input.group.tradeCount,
    reliability: input.group.reliability,
    rankingScore: input.rankingScore,
  }
}

function formatGroupDetail(group: DailyGroupAggregate): string {
  const parts = [
    `${group.dayCount} trading ${group.dayCount === 1 ? "day" : "days"}`,
    `${formatPsychologyMoney(group.totalPnL)} total P&L`,
    `${formatPsychologyMoney(group.avgDailyPnL)} avg / day`,
  ]
  if (group.winRate != null) {
    parts.push(`${formatPsychologyWinRate(group.winRate)} win rate`)
  }
  parts.push(`${group.tradeCount} trades`)
  parts.push(reliabilityNote(group.reliability))
  return parts.join(" · ")
}

function compareDetail(
  better: DailyGroupAggregate,
  worse: DailyGroupAggregate,
  betterLabel: string,
  worseLabel: string
): string {
  return (
    `${betterLabel}: ${formatPsychologyMoney(better.avgDailyPnL)}/day (${better.dayCount}d) vs ` +
    `${worseLabel}: ${formatPsychologyMoney(worse.avgDailyPnL)}/day (${worse.dayCount}d) · ` +
    `${better.tradeCount + worse.tradeCount} trades · ${reliabilityNote(
      resolveMatchedDayReliability(
        better.dayCount + worse.dayCount,
        better.tradeCount + worse.tradeCount
      )
    )} — association only, not causation`
  )
}

type RatingSplit = {
  goodLabel: string
  poorLabel: string
  read: (day: MatchedTradingDay) => number | null
  goodWhen: (rating: number) => boolean
  poorWhen: (rating: number) => boolean
}

function ratingSplitCards(
  id: string,
  sectionTitle: string,
  category: PsychologyInsightCategory,
  allDays: MatchedTradingDay[],
  split: RatingSplit
): PsychologyInsightCard[] {
  const goodDays = allDays.filter((d) => {
    const r = split.read(d)
    return r != null && split.goodWhen(r)
  })
  const poorDays = allDays.filter((d) => {
    const r = split.read(d)
    return r != null && split.poorWhen(r)
  })
  const cards: PsychologyInsightCard[] = []

  if (goodDays.length > 0 && poorDays.length > 0) {
    const g = aggregateDays(split.goodLabel, goodDays)
    const p = aggregateDays(split.poorLabel, poorDays)
    const gBetter = g.avgDailyPnL >= p.avgDailyPnL
    const [better, worse, bLabel, wLabel] = gBetter
      ? [g, p, split.goodLabel, split.poorLabel]
      : [p, g, split.poorLabel, split.goodLabel]
    cards.push(
      makeDailyCard({
        id: `${id}.compare`,
        category,
        sectionTitle,
        headline: `${bLabel} vs ${wLabel} (daily P&L)`,
        detail: compareDetail(better, worse, bLabel, wLabel),
        group: better,
        rankingScore: 0.7,
      })
    )
    return cards
  }

  if (goodDays.length > 0) {
    const g = aggregateDays(split.goodLabel, goodDays)
    cards.push(
      makeDailyCard({
        id: `${id}.good`,
        category,
        sectionTitle,
        headline: `${split.goodLabel} days in your sample`,
        detail: formatGroupDetail(g),
        group: g,
        rankingScore: 0.45,
      })
    )
  }
  if (poorDays.length > 0) {
    const p = aggregateDays(split.poorLabel, poorDays)
    cards.push(
      makeDailyCard({
        id: `${id}.poor`,
        category,
        sectionTitle,
        headline: `${split.poorLabel} days in your sample`,
        detail: formatGroupDetail(p),
        group: p,
        rankingScore: 0.4,
      })
    )
  }
  return cards
}

function buildCheckInDimensionCards(days: MatchedTradingDay[]): PsychologyInsightCard[] {
  if (days.length === 0) return []

  const cards: PsychologyInsightCard[] = []

  cards.push(
    ...ratingSplitCards("sleepQuality", "Sleep", "sleep", days, {
      goodLabel: "Good sleep (4–5)",
      poorLabel: "Poor sleep (1–2)",
      read: (d) => d.checkIn.sleepQuality,
      goodWhen: (r) => r >= 4,
      poorWhen: (r) => r <= 2,
    })
  )

  cards.push(
    ...ratingSplitCards("focus", "Focus", "mentalState", days, {
      goodLabel: "Focused (4–5)",
      poorLabel: "Unfocused (1–2)",
      read: (d) => d.checkIn.focusLevel,
      goodWhen: (r) => r >= 4,
      poorWhen: (r) => r <= 2,
    })
  )

  cards.push(
    ...ratingSplitCards("morning", "Morning mood", "mentalState", days, {
      goodLabel: "Positive morning (4–5)",
      poorLabel: "Low morning (1–2)",
      read: (d) => d.checkIn.morningRating,
      goodWhen: (r) => r >= 4,
      poorWhen: (r) => r <= 2,
    })
  )

  cards.push(
    ...ratingSplitCards("stress", "Stress", "mentalState", days, {
      goodLabel: "Low stress (1–2)",
      poorLabel: "High stress (4–5)",
      read: (d) => d.checkIn.stressLevel,
      goodWhen: (r) => r <= 2,
      poorWhen: (r) => r >= 4,
    })
  )

  cards.push(
    ...ratingSplitCards("energy", "Energy", "mentalState", days, {
      goodLabel: "High energy (4–5)",
      poorLabel: "Low energy (1–2)",
      read: (d) => d.checkIn.energyLevel,
      goodWhen: (r) => r >= 4,
      poorWhen: (r) => r <= 2,
    })
  )

  return cards
}

function buildOverviewCard(days: MatchedTradingDay[]): PsychologyInsightCard | null {
  if (days.length === 0) return null
  const group = aggregateDays("Matched check-in days", days)
  return {
    id: "matchedDays.overview",
    category: "combined",
    sectionTitle: "Matched days",
    headline: `${group.dayCount} trading ${group.dayCount === 1 ? "day" : "days"} with check-ins`,
    detail: formatGroupDetail(group),
    sampleSize: group.tradeCount,
    reliability: group.reliability,
    rankingScore: 1,
  }
}

function mapTradeForPsychology(trade: TradeWithPnL): PsychologyReportTrade | null {
  const entry = String(trade.entry_time ?? trade.created_at ?? "").trim()
  if (!entry) return null
  const entryAtMs = new Date(entry).getTime()
  if (Number.isNaN(entryAtMs)) return null
  const id = String((trade as { id?: string }).id ?? entry)
  const raw = trade as Record<string, unknown>
  return {
    id,
    entryAtMs,
    entry_time: entry,
    created_at: trade.created_at ?? null,
    pnl: readTradePnL(trade),
    rr: null,
    emotion: (raw.emotion as string | null) ?? null,
    confidence: (raw.confidence as number | null) ?? null,
    followedPlan: (raw.followed_plan as boolean | null) ?? null,
    executionRating: (raw.execution_rating as number | null) ?? null,
  }
}

function readTradePnL(trade: TradeWithPnL): number {
  const raw = trade.pnl
  const value = typeof raw === "string" ? Number.parseFloat(raw) : Number(raw)
  return Number.isFinite(value) ? value : 0
}

function buildTradeTagCards(trades: readonly TradeWithPnL[]): PsychologyInsightCard[] {
  const mapped = trades.flatMap((t) => {
    const row = mapTradeForPsychology(t)
    return row ? [row] : []
  })
  if (mapped.length === 0) return []

  const cards: PsychologyInsightCard[] = []

  const highConf = mapped.filter((t) => (t.confidence ?? 0) >= 4)
  const lowConf = mapped.filter((t) => (t.confidence ?? 0) <= 2 && t.confidence != null)
  if (highConf.length >= 1 && lowConf.length >= 1) {
    const hi = psychologyTradeMetrics(highConf)
    const lo = psychologyTradeMetrics(lowConf)
    hi.reliability = resolveMatchedDayReliability(0, hi.tradeCount)
    lo.reliability = resolveMatchedDayReliability(0, lo.tradeCount)
    cards.push({
      id: "trade.confidence.compare",
      category: "conviction",
      sectionTitle: "Confidence",
      headline: "High vs low confidence trades",
      detail: `4–5: ${formatPsychologyMoney(hi.averagePnL ?? 0)} avg (${hi.tradeCount} trades) vs 1–2: ${formatPsychologyMoney(lo.averagePnL ?? 0)} avg (${lo.tradeCount} trades) · ${reliabilityNote(hi.reliability)}`,
      sampleSize: hi.tradeCount + lo.tradeCount,
      reliability: resolveMatchedDayReliability(0, hi.tradeCount + lo.tradeCount),
      rankingScore: 0.65,
    })
  } else if (highConf.length >= 1) {
    const hi = psychologyTradeMetrics(highConf)
    hi.reliability = resolveMatchedDayReliability(0, hi.tradeCount)
    cards.push({
      id: "trade.confidence.high",
      category: "conviction",
      sectionTitle: "Confidence",
      headline: "High-confidence trades (4–5)",
      detail: `${formatPsychologyMoney(hi.totalPnL)} total · ${formatPsychologyWinRate(hi.winRate)} win rate · ${hi.tradeCount} trades · ${reliabilityNote(hi.reliability)}`,
      sampleSize: hi.tradeCount,
      reliability: hi.reliability,
      rankingScore: 0.5,
    })
  }

  const followed = mapped.filter((t) => t.followedPlan === true)
  const broken = mapped.filter((t) => t.followedPlan === false)
  if (followed.length >= 1 && broken.length >= 1) {
    const f = psychologyTradeMetrics(followed)
    const b = psychologyTradeMetrics(broken)
    cards.push({
      id: "trade.plan.compare",
      category: "discipline",
      sectionTitle: "Discipline",
      headline: "Plan followed vs not followed",
      detail: `Followed: ${formatPsychologyMoney(f.averagePnL ?? 0)} avg (${f.tradeCount}) vs not: ${formatPsychologyMoney(b.averagePnL ?? 0)} avg (${b.tradeCount}) · ${reliabilityNote(resolveMatchedDayReliability(0, f.tradeCount + b.tradeCount))}`,
      sampleSize: f.tradeCount + b.tradeCount,
      reliability: resolveMatchedDayReliability(0, f.tradeCount + b.tradeCount),
      rankingScore: 0.75,
    })
  }

  const withEmotion = mapped.filter((t) => String(t.emotion ?? "").trim())
  if (withEmotion.length >= 3) {
    const byEmotion = new Map<string, PsychologyReportTrade[]>()
    for (const t of withEmotion) {
      const key = String(t.emotion).trim()
      const list = byEmotion.get(key) ?? []
      list.push(t)
      byEmotion.set(key, list)
    }
    let best: { emotion: string; metrics: ReturnType<typeof psychologyTradeMetrics> } | null =
      null
    for (const [emotion, rows] of byEmotion) {
      if (rows.length < 1) continue
      const metrics = psychologyTradeMetrics(rows)
      if (!best || (metrics.totalPnL ?? 0) > (best.metrics.totalPnL ?? 0)) {
        best = { emotion, metrics }
      }
    }
    if (best && best.metrics.tradeCount >= 1) {
      cards.push({
        id: "trade.emotion.top",
        category: "emotion",
        sectionTitle: "Emotion",
        headline: `"${best.emotion}" tagged trades`,
        detail: `${formatPsychologyMoney(best.metrics.totalPnL)} total · ${formatPsychologyWinRate(best.metrics.winRate)} win rate · ${best.metrics.tradeCount} trades · ${reliabilityNote(resolveMatchedDayReliability(0, best.metrics.tradeCount))}`,
        sampleSize: best.metrics.tradeCount,
        reliability: resolveMatchedDayReliability(0, best.metrics.tradeCount),
        rankingScore: 0.35,
      })
    }
  }

  return cards
}

/** Primary dashboard insight builder — works from one matched day upward. */
export function buildEarlyPsychologyInsightCards(
  trades: readonly TradeWithPnL[],
  checkIns: readonly TraderDailyCheckIn[]
): PsychologyInsightCard[] {
  const complete = checkIns.filter(isCompleteCheckIn)
  const matchedDays = buildMatchedTradingDays(trades, complete)
  const cards: PsychologyInsightCard[] = []

  const overview = buildOverviewCard(matchedDays)
  if (overview) cards.push(overview)

  cards.push(...buildCheckInDimensionCards(matchedDays))
  cards.push(...buildTradeTagCards(trades))

  const seen = new Set<string>()
  const unique = cards.filter((c) => {
    if (seen.has(c.id)) return false
    seen.add(c.id)
    return true
  })

  unique.sort((a, b) => b.rankingScore - a.rankingScore)
  return unique.slice(0, 8)
}

export function mergePsychologyInsightCards(
  early: readonly PsychologyInsightCard[],
  fromReport: readonly PsychologyInsightCard[]
): PsychologyInsightCard[] {
  if (fromReport.length > 0) {
    const ids = new Set(fromReport.map((c) => c.id))
    const extras = early.filter((c) => !ids.has(c.id))
    return [...fromReport, ...extras].slice(0, 8)
  }
  return early.slice(0, 8)
}

export function hasMatchedPsychologyData(
  trades: readonly TradeWithPnL[],
  checkIns: readonly TraderDailyCheckIn[]
): boolean {
  return buildMatchedTradingDays(trades, checkIns.filter(isCompleteCheckIn)).length > 0
}

/** For tests — expose enrich path used by full report (unchanged). */
export function enrichTradesWithCheckIns(
  trades: readonly PsychologyReportTrade[],
  checkIns: readonly TraderDailyCheckIn[]
) {
  return enrichPsychologyTrades(trades, checkIns)
}
