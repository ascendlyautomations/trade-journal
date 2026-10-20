import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import { stressLabel } from "../dailyCheckIn/types.ts"
import { formatHours } from "./display.ts"
import { psychologyTradeMetrics } from "./reports/metrics.ts"
import {
  formatPsychologyMoney,
  formatPsychologyRatio,
  formatPsychologyWinRate,
} from "./reports/format.ts"
import type { PsychologyGroupMetrics, PsychologyReportTrade } from "./reports/types.ts"
import { psychologyTradeDateKey } from "./tradeDateKey.ts"

export type CheckInHistoryContentFilter = "all" | "trades" | "psychology"

export type CheckInHistoryDaySummary = {
  dateKey: string
  checkIn: TraderDailyCheckIn | null
  tradeCount: number
  totalPnL: number
  winCount: number
  lossCount: number
}

export type CheckInDayDetail = {
  dateKey: string
  checkIn: TraderDailyCheckIn | null
  trades: PsychologyReportTrade[]
  metrics: PsychologyGroupMetrics
}

export function psychologyPreviewParts(checkIn: TraderDailyCheckIn): string[] {
  const parts: string[] = []
  if (checkIn.sleepHours != null) {
    parts.push(`${formatHours(checkIn.sleepHours)} Sleep`)
  }
  if (checkIn.sleepQuality != null) {
    parts.push(`Sleep Quality ${checkIn.sleepQuality}/5`)
  }
  if (checkIn.morningRating != null) {
    parts.push(`Morning ${checkIn.morningRating}/5`)
  }
  if (checkIn.stressLevel != null) {
    parts.push(`Stress ${stressLabel(checkIn.stressLevel)}`)
  }
  if (checkIn.energyLevel != null) {
    parts.push(`Energy ${checkIn.energyLevel}/5`)
  }
  if (checkIn.focusLevel != null) {
    parts.push(`Focus ${checkIn.focusLevel}/5`)
  }
  const notes = checkIn.notes?.trim()
  if (notes) parts.push(notes)
  return parts
}

export function checkInHistoryDayHasPsychology(
  summary: CheckInHistoryDaySummary
): boolean {
  if (!summary.checkIn) return false
  return psychologyPreviewParts(summary.checkIn).length > 0
}

/** Distinct days that appear under Check-In History → Psychology. */
export function countPsychologyCheckInHistoryDays(
  checkIns: readonly TraderDailyCheckIn[]
): number {
  const dates = new Set<string>()
  for (const row of checkIns) {
    if (psychologyPreviewParts(row).length > 0) {
      dates.add(row.checkInDate)
    }
  }
  return dates.size
}

export function checkInHistoryDayMatchesFilter(
  summary: CheckInHistoryDaySummary,
  filter: CheckInHistoryContentFilter
): boolean {
  switch (filter) {
    case "all":
      return true
    case "trades":
      return summary.tradeCount > 0
    case "psychology":
      return checkInHistoryDayHasPsychology(summary)
  }
}

/** iOS `CheckInHistoryAggregator.buildSummaries`. */
export function buildCheckInHistorySummaries(
  checkIns: readonly TraderDailyCheckIn[],
  trades: readonly PsychologyReportTrade[],
  dayLimit = 90
): CheckInHistoryDaySummary[] {
  const checkInByDate = new Map(checkIns.map((row) => [row.checkInDate, row]))
  const statsByDate = new Map<
    string,
    { tradeCount: number; totalPnL: number; winCount: number; lossCount: number }
  >()

  for (const trade of trades) {
    const key = psychologyTradeDateKey(trade)
    if (!key) continue
    const stats = statsByDate.get(key) ?? {
      tradeCount: 0,
      totalPnL: 0,
      winCount: 0,
      lossCount: 0,
    }
    stats.tradeCount += 1
    const pnl = Number.isFinite(trade.pnl) ? trade.pnl : 0
    stats.totalPnL += pnl
    if (pnl > 0) stats.winCount += 1
    else if (pnl < 0) stats.lossCount += 1
    statsByDate.set(key, stats)
  }

  const dateKeys = new Set<string>([
    ...checkInByDate.keys(),
    ...statsByDate.keys(),
  ])
  return [...dateKeys]
    .sort((a, b) => b.localeCompare(a))
    .slice(0, dayLimit)
    .map((dateKey) => {
      const stats = statsByDate.get(dateKey) ?? {
        tradeCount: 0,
        totalPnL: 0,
        winCount: 0,
        lossCount: 0,
      }
      return {
        dateKey,
        checkIn: checkInByDate.get(dateKey) ?? null,
        tradeCount: stats.tradeCount,
        totalPnL: stats.totalPnL,
        winCount: stats.winCount,
        lossCount: stats.lossCount,
      }
    })
}

export function buildCheckInDayDetail(
  dateKey: string,
  checkIns: readonly TraderDailyCheckIn[],
  trades: readonly PsychologyReportTrade[]
): CheckInDayDetail {
  const dayTrades = trades
    .filter((trade) => psychologyTradeDateKey(trade) === dateKey)
    .sort((a, b) => b.entryAtMs - a.entryAtMs)
  const checkIn = checkIns.find((row) => row.checkInDate === dateKey) ?? null
  return {
    dateKey,
    checkIn,
    trades: dayTrades,
    metrics: psychologyTradeMetrics(dayTrades),
  }
}

export function formatCheckInHistoryDateLabel(dateKey: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey)
  if (!match) return dateKey
  const date = new Date(
    Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
  )
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" })
}

export function formatCheckInHistoryDayTitle(dateKey: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey)
  if (!match) return dateKey
  const date = new Date(
    Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
  )
  return date.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  })
}

export function formatCheckInHistoryTradeLine(summary: CheckInHistoryDaySummary): string {
  const parts: string[] = []
  const sign = summary.totalPnL >= 0 ? "+" : ""
  parts.push(`${sign}${formatPsychologyMoney(summary.totalPnL)} P&L`)
  parts.push(`${summary.tradeCount} Trades`)
  if (summary.tradeCount > 0) {
    const rate = summary.winCount / summary.tradeCount
    parts.push(`${formatPsychologyWinRate(rate)} Win`)
  }
  return parts.join(" · ")
}

export function formatCheckInDayProfitFactor(
  metrics: PsychologyGroupMetrics
): string {
  return formatPsychologyRatio(metrics.profitFactor)
}
