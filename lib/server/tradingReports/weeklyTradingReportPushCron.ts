import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isDemoUserId } from "@/lib/demo/constants"
import { notify } from "@/lib/server/notifications/NotificationService"
import { saturdayCurrentWeekReport } from "@/lib/tradingReports/tradingReportPeriods"
import { isWeeklyTradingReportPushWindow } from "@/lib/server/tradingReports/weeklyTradingReportPushWindow"

const WEEKLY_TITLE = "Your Weekly Trading Report is Ready"

export { isWeeklyTradingReportPushWindow }

async function eligibleUserIds(
  startKey: string,
  endKey: string
): Promise<string[]> {
  const { data, error } = await supabaseServiceRole.rpc(
    "weekly_trading_report_eligible_user_ids",
    { p_start: startKey, p_end: endKey }
  )
  if (error) throw new Error(error.message)

  const raw = Array.isArray(data) ? data : []
  const ids = new Set<string>()
  for (const value of raw) {
    const id = typeof value === "string" ? value.trim() : ""
    if (id && !isDemoUserId(id)) ids.add(id)
  }
  return [...ids]
}

export type WeeklyTradingReportPushResult = {
  skipped?: boolean
  reason?: string
  periodId?: string
  startKey?: string
  endKey?: string
  eligibleUsers?: number
  sent?: number
  deduped?: number
  pushRetried?: number
  pushPending?: number
  preferenceSkipped?: number
  failed?: number
}

async function notifyEligibleUser(
  userId: string,
  target: ReturnType<typeof saturdayCurrentWeekReport>
): Promise<
  | "sent"
  | "deduped"
  | "preferences"
  | "push_retried"
  | "push_pending"
  | "failed"
> {
  const result = await notify({
    type: "trading_report",
    actorUserId: userId,
    periodKey: target.periodId,
    periodId: target.periodId,
    kind: "weekly",
    title: WEEKLY_TITLE,
    href: target.href,
  })
  if (!result.ok) return "failed"
  if (result.skipped && result.reason === "dedupe") return "deduped"
  if (result.skipped && result.reason === "preferences") return "preferences"
  if (result.reason === "push_retried") return "push_retried"
  if (result.reason === "push_pending") return "push_pending"
  return "sent"
}

function tallyResult(
  outcome: Awaited<ReturnType<typeof notifyEligibleUser>>,
  counts: {
    sent: number
    deduped: number
    pushRetried: number
    pushPending: number
    preferenceSkipped: number
    failed: number
  }
) {
  if (outcome === "failed") counts.failed += 1
  else if (outcome === "deduped") counts.deduped += 1
  else if (outcome === "preferences") counts.preferenceSkipped += 1
  else if (outcome === "push_retried") counts.pushRetried += 1
  else if (outcome === "push_pending") counts.pushPending += 1
  else counts.sent += 1
}

/**
 * One eligible account, ignoring the Saturday clock.
 * Temporary production test entry. Still refuses ineligible users.
 */
export async function runWeeklyTradingReportPushForUser(
  userId: string,
  now = new Date()
): Promise<WeeklyTradingReportPushResult> {
  const target = saturdayCurrentWeekReport(now)
  const eligible = await eligibleUserIds(target.startKey, target.endKey)
  if (!eligible.includes(userId)) {
    return {
      skipped: true,
      reason: "not_eligible",
      periodId: target.periodId,
      startKey: target.startKey,
      endKey: target.endKey,
      eligibleUsers: eligible.length,
    }
  }

  const counts = {
    sent: 0,
    deduped: 0,
    pushRetried: 0,
    pushPending: 0,
    preferenceSkipped: 0,
    failed: 0,
  }
  tallyResult(await notifyEligibleUser(userId, target), counts)
  return {
    periodId: target.periodId,
    startKey: target.startKey,
    endKey: target.endKey,
    eligibleUsers: 1,
    ...counts,
  }
}

/** Saturday ET — notify users who traded in the current Eastern week. */
export async function runWeeklyTradingReportPushCron(
  now = new Date()
): Promise<WeeklyTradingReportPushResult> {
  if (!isWeeklyTradingReportPushWindow(now)) {
    return { skipped: true, reason: "outside_push_window" }
  }

  const target = saturdayCurrentWeekReport(now)
  const userIds = await eligibleUserIds(target.startKey, target.endKey)

  const counts = {
    sent: 0,
    deduped: 0,
    pushRetried: 0,
    pushPending: 0,
    preferenceSkipped: 0,
    failed: 0,
  }

  for (const userId of userIds) {
    tallyResult(await notifyEligibleUser(userId, target), counts)
  }

  return {
    periodId: target.periodId,
    startKey: target.startKey,
    endKey: target.endKey,
    eligibleUsers: userIds.length,
    ...counts,
  }
}
