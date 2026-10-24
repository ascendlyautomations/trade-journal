import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isDemoUserId } from "@/lib/demo/constants"
import { notify } from "@/lib/server/notifications/NotificationService"
import {
  getTradingReportPeriodBounds,
  tradingReportPeriodId,
} from "@/lib/tradingReports/tradingReportPeriods"

const EASTERN = "America/New_York"
const WEEKLY_TITLE = "Your Weekly Trading Report is Ready"
const PERIOD_KEY = "weekly_last" as const

const easternWallClockFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: EASTERN,
  weekday: "short",
  hour: "numeric",
  minute: "numeric",
  hourCycle: "h23",
})

/**
 * Hobby cron: Saturday 17:00 UTC (+ up to ~59m delay).
 * Eastern: ~12:00–12:59 EST / ~13:00–13:59 EDT — window 12:00–14:59 ET Saturday.
 */
export function isWeeklyTradingReportPushWindow(now = new Date()): boolean {
  const parts = easternWallClockFormatter.formatToParts(now)
  const weekday = parts.find((p) => p.type === "weekday")?.value ?? ""
  if (weekday !== "Sat") return false
  const hour = Number.parseInt(
    parts.find((p) => p.type === "hour")?.value ?? "",
    10
  )
  const minute = Number.parseInt(
    parts.find((p) => p.type === "minute")?.value ?? "",
    10
  )
  if (!Number.isFinite(hour) || !Number.isFinite(minute)) return false
  const minutesSinceMidnight = hour * 60 + minute
  const windowStart = 12 * 60
  const windowEnd = 14 * 60 + 59
  return minutesSinceMidnight >= windowStart && minutesSinceMidnight <= windowEnd
}

async function distinctUserIdsWithTradeInBounds(
  startIso: string,
  endIso: string
): Promise<string[]> {
  const ids = new Set<string>()

  const collect = (rows: { user_id: string | null }[] | null) => {
    for (const row of rows ?? []) {
      const id = row.user_id?.trim()
      if (id && !isDemoUserId(id)) ids.add(id)
    }
  }

  const [byEntry, byExit, byCreated] = await Promise.all([
    supabaseServiceRole
      .from("trades")
      .select("user_id")
      .neq("mode", "backtest")
      .gte("entry_time", startIso)
      .lte("entry_time", endIso),
    supabaseServiceRole
      .from("trades")
      .select("user_id")
      .neq("mode", "backtest")
      .gte("exit_time", startIso)
      .lte("exit_time", endIso),
    supabaseServiceRole
      .from("trades")
      .select("user_id")
      .neq("mode", "backtest")
      .is("entry_time", null)
      .is("exit_time", null)
      .gte("created_at", startIso)
      .lte("created_at", endIso),
  ])

  if (byEntry.error) throw new Error(byEntry.error.message)
  if (byExit.error) throw new Error(byExit.error.message)
  if (byCreated.error) throw new Error(byCreated.error.message)

  collect(byEntry.data)
  collect(byExit.data)
  collect(byCreated.data)

  return [...ids]
}

export type WeeklyTradingReportPushResult = {
  skipped?: boolean
  reason?: string
  periodId?: string
  eligibleUsers?: number
  sent?: number
  deduped?: number
  preferenceSkipped?: number
  failed?: number
}

/** Saturday noon ET — weekly report push for users with trades in `weekly_last`. */
export async function runWeeklyTradingReportPushCron(
  now = new Date()
): Promise<WeeklyTradingReportPushResult> {
  if (!isWeeklyTradingReportPushWindow(now)) {
    return { skipped: true, reason: "outside_push_window" }
  }

  const bounds = getTradingReportPeriodBounds(PERIOD_KEY, now)
  const periodId = tradingReportPeriodId(PERIOD_KEY, now)
  const startIso = bounds.start.toISOString()
  const endIso = bounds.end.toISOString()
  const href = `/dashboard?report=${encodeURIComponent(PERIOD_KEY)}`

  const userIds = await distinctUserIdsWithTradeInBounds(startIso, endIso)

  let sent = 0
  let deduped = 0
  let preferenceSkipped = 0
  let failed = 0

  for (const userId of userIds) {
    const result = await notify({
      type: "trading_report",
      actorUserId: userId,
      periodKey: PERIOD_KEY,
      periodId,
      kind: "weekly",
      title: WEEKLY_TITLE,
      href,
    })

    if (!result.ok) {
      failed += 1
      continue
    }
    if (result.skipped && result.reason === "dedupe") {
      deduped += 1
      continue
    }
    if (result.skipped) {
      preferenceSkipped += 1
      continue
    }
    sent += 1
  }

  return {
    periodId,
    eligibleUsers: userIds.length,
    sent,
    deduped,
    preferenceSkipped,
    failed,
  }
}
