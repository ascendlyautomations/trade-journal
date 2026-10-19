import {
  addCalendarDaysToDateKey,
  checkInDateKey,
} from "../../dailyCheckIn/dateKey.ts"
import { psychologyTradeDateKey } from "../tradeDateKey.ts"
import {
  isPeriodicPsychologyTemplate,
  psychologyReportID,
} from "./catalog.ts"
import type {
  PsychologyReportPeriodRef,
  PsychologyReportTemplate,
  PsychologyReportTrade,
} from "./types.ts"

const WEEKDAY_NAMES = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
] as const

const easternWeekdayFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: "America/New_York",
  weekday: "long",
})

export type PsychologyPeriodBounds = {
  ref: PsychologyReportPeriodRef
  startMs: number
  endMs: number
  startDateKey: string
  endDateKey: string
  dateRangeLabel: string
}

export function startOfEasternDay(dateKey: string): Date {
  const est = Date.parse(`${dateKey}T00:00:00-05:00`)
  const edt = Date.parse(`${dateKey}T00:00:00-04:00`)
  for (const timestamp of [est, edt]) {
    if (!Number.isFinite(timestamp)) continue
    const instant = new Date(timestamp)
    if (checkInDateKey(instant) !== dateKey) continue
    if (checkInDateKey(new Date(timestamp - 1)) === dateKey) continue
    return instant
  }
  return new Date(est)
}

export function endOfEasternDay(dateKey: string): Date {
  const next = addCalendarDaysToDateKey(dateKey, 1)
  return new Date(startOfEasternDay(next).getTime() - 1)
}

function easternWeekdayIndex(dateKey: string): number {
  const name = easternWeekdayFormatter.format(startOfEasternDay(dateKey))
  const index = WEEKDAY_NAMES.indexOf(name as (typeof WEEKDAY_NAMES)[number])
  return index >= 0 ? index : 1
}

export function mondayOfEasternWeek(dateKey: string): string {
  const weekday = easternWeekdayIndex(dateKey)
  const diff = weekday === 0 ? -6 : 1 - weekday
  return addCalendarDaysToDateKey(dateKey, diff)
}

export function psychologyReportDateRangeLabel(
  startKey: string,
  endKey: string,
  kind: "weekly" | "monthly" | "rolling"
): string {
  if (kind === "rolling") return "Last 90 days"
  const start = startOfEasternDay(startKey)
  const end = startOfEasternDay(endKey)
  if (startKey === endKey) {
    return start.toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
      timeZone: "America/New_York",
    })
  }
  if (kind === "monthly" && startKey.endsWith("-01")) {
    const [year, month] = startKey.split("-").map(Number)
    const lastDay = addCalendarDaysToDateKey(
      addCalendarDaysToDateKey(`${year}-${String(month).padStart(2, "0")}-01`, 32).slice(0, 7) + "-01",
      -1
    )
    if (endKey === lastDay) {
      return start.toLocaleDateString("en-US", {
        month: "long",
        year: "numeric",
        timeZone: "America/New_York",
      })
    }
  }
  const startYear = startKey.slice(0, 4)
  const endYear = endKey.slice(0, 4)
  const startLabel = start.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    ...(startYear !== endYear ? { year: "numeric" as const } : {}),
    timeZone: "America/New_York",
  })
  const endLabel = end.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    timeZone: "America/New_York",
  })
  return `${startLabel} – ${endLabel}`
}

function rollingBounds(
  template: PsychologyReportTemplate,
  now: Date
): PsychologyPeriodBounds {
  const today = checkInDateKey(now)
  const startKey = addCalendarDaysToDateKey(today, -89)
  const ref = { template, periodID: "rolling:90d" }
  return {
    ref,
    startMs: startOfEasternDay(startKey).getTime(),
    endMs: endOfEasternDay(today).getTime(),
    startDateKey: startKey,
    endDateKey: today,
    dateRangeLabel: "Last 90 days",
  }
}

function weeklyBounds(periodID: string, now: Date, template: PsychologyReportTemplate): PsychologyPeriodBounds {
  const mondayKey = periodID.startsWith("week:")
    ? periodID.slice("week:".length)
    : mondayOfEasternWeek(checkInDateKey(now))
  const sundayKey = addCalendarDaysToDateKey(mondayKey, 6)
  const today = checkInDateKey(now)
  const endKey = sundayKey > today ? today : sundayKey
  const ref = { template, periodID: `week:${mondayKey}` }
  return {
    ref,
    startMs: startOfEasternDay(mondayKey).getTime(),
    endMs: endOfEasternDay(endKey).getTime(),
    startDateKey: mondayKey,
    endDateKey: endKey,
    dateRangeLabel: psychologyReportDateRangeLabel(mondayKey, endKey, "weekly"),
  }
}

function monthlyBounds(periodID: string, now: Date, template: PsychologyReportTemplate): PsychologyPeriodBounds {
  const today = checkInDateKey(now)
  const raw = periodID.startsWith("month:") ? periodID.slice("month:".length) : today.slice(0, 7)
  const [year, month] = raw.split("-").map(Number)
  const startKey = `${year}-${String(month).padStart(2, "0")}-01`
  const nextMonthStart = month === 12
    ? `${year + 1}-01-01`
    : `${year}-${String(month + 1).padStart(2, "0")}-01`
  const lastDay = addCalendarDaysToDateKey(nextMonthStart, -1)
  const isCurrentMonth = today.startsWith(raw)
  const endKey = isCurrentMonth ? today : lastDay
  const ref = { template, periodID: `month:${raw}` }
  return {
    ref,
    startMs: startOfEasternDay(startKey).getTime(),
    endMs: endOfEasternDay(endKey).getTime(),
    startDateKey: startKey,
    endDateKey: endKey,
    dateRangeLabel: psychologyReportDateRangeLabel(startKey, endKey, "monthly"),
  }
}

export function psychologyPeriodBounds(
  ref: PsychologyReportPeriodRef,
  now: Date = new Date()
): PsychologyPeriodBounds {
  if (ref.template === "weekly" || ref.periodID.startsWith("week:")) {
    return weeklyBounds(ref.periodID, now, ref.template)
  }
  if (ref.template === "monthly" || ref.periodID.startsWith("month:")) {
    return monthlyBounds(ref.periodID, now, ref.template)
  }
  return rollingBounds(ref.template, now)
}

function earliestTradeDateKey(trades: readonly PsychologyReportTrade[]): string | null {
  let earliest: string | null = null
  for (const trade of trades) {
    const key = psychologyTradeDateKey(trade)
    if (!key) continue
    if (!earliest || key < earliest) earliest = key
  }
  return earliest
}

export function weeklyPsychologyRefs(
  earliestKey: string,
  now: Date,
  limit: number
): PsychologyReportPeriodRef[] {
  const today = checkInDateKey(now)
  let monday = mondayOfEasternWeek(today)
  const refs: PsychologyReportPeriodRef[] = []
  for (let index = 0; index < limit; index += 1) {
    if (monday < earliestKey) break
    refs.push({ template: "weekly", periodID: `week:${monday}` })
    monday = addCalendarDaysToDateKey(monday, -7)
  }
  return refs
}

export function monthlyPsychologyRefs(
  earliestKey: string,
  now: Date,
  limit: number
): PsychologyReportPeriodRef[] {
  const today = checkInDateKey(now)
  let year = Number(today.slice(0, 4))
  let month = Number(today.slice(5, 7))
  const refs: PsychologyReportPeriodRef[] = []
  for (let index = 0; index < limit; index += 1) {
    const id = `month:${year}-${String(month).padStart(2, "0")}`
    refs.push({ template: "monthly", periodID: id })
    const startKey = `${year}-${String(month).padStart(2, "0")}-01`
    if (startKey < earliestKey) break
    month -= 1
    if (month < 1) {
      month = 12
      year -= 1
    }
  }
  return refs
}

export function availablePsychologyCatalog(
  trades: readonly PsychologyReportTrade[],
  now: Date = new Date(),
  maxWeekly = 12,
  maxMonthly = 6
): PsychologyReportPeriodRef[] {
  const thematics: PsychologyReportPeriodRef[] = [
    "sleepPerformance",
    "discipline",
    "emotions",
    "afterLosses",
    "mentalState",
    "tradeFrequency",
  ].map((template) => ({
    template: template as PsychologyReportTemplate,
    periodID: "rolling:90d",
  }))

  const earliest = earliestTradeDateKey(trades)
  if (!earliest) {
    const today = checkInDateKey(now)
    return [
      { template: "weekly", periodID: `week:${mondayOfEasternWeek(today)}` },
      { template: "monthly", periodID: `month:${today.slice(0, 7)}` },
      ...thematics,
    ]
  }

  return [
    ...monthlyPsychologyRefs(earliest, now, maxMonthly),
    ...weeklyPsychologyRefs(earliest, now, maxWeekly),
    ...thematics,
  ]
}

export function filterTradesForPeriod(
  trades: readonly PsychologyReportTrade[],
  bounds: PsychologyPeriodBounds
): PsychologyReportTrade[] {
  return trades.filter(
    (trade) => trade.entryAtMs >= bounds.startMs && trade.entryAtMs <= bounds.endMs
  )
}

export function catalogCardPeriods(
  catalog: readonly PsychologyReportPeriodRef[],
  template: PsychologyReportTemplate
): PsychologyReportPeriodRef[] {
  return catalog.filter((ref) => ref.template === template)
}

export function reportIDForRef(ref: PsychologyReportPeriodRef): string {
  return psychologyReportID(ref.template, ref.periodID)
}

export function defaultPeriodForTemplate(
  catalog: readonly PsychologyReportPeriodRef[],
  template: PsychologyReportTemplate
): PsychologyReportPeriodRef {
  return (
    catalog.find((ref) => ref.template === template) ??
    (isPeriodicPsychologyTemplate(template)
      ? { template, periodID: template === "weekly" ? "week:" : "month:" }
      : { template, periodID: "rolling:90d" })
  )
}
