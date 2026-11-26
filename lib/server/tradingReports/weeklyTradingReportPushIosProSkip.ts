import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

/**
 * Skip Saturday server APNs only when an iOS install has confirmed local Performance Report
 * reminders are scheduled (`performance_report_local_reminders_active`). Token presence alone
 * is not enough — the app sets the flag after verifying pending weekly + monthly requests.
 */
export async function shouldSkipWeeklyTradingReportServerPushForUser(
  userId: string
): Promise<boolean> {
  const trimmed = userId.trim()
  if (!trimmed) return false

  const { data, error } = await supabaseServiceRole
    .from("device_push_tokens")
    .select("id")
    .eq("user_id", trimmed)
    .eq("platform", "ios")
    .eq("performance_report_local_reminders_active", true)
    .limit(1)

  if (error) {
    console.error(
      "[trading-reports/notify] local performance reminder probe failed",
      error
    )
    return false
  }
  return (data?.length ?? 0) > 0
}