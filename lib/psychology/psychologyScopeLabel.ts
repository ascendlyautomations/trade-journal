import { dashboardTimeframeCapsuleLabel } from "@/lib/dashboardTimeframeLabels"

/** Human-readable scope for psychology analytics (matches dashboard filters). */
export function formatPsychologyDashboardScopeLabel(options: {
  timeFilter: string
  selectedDate?: string
  customRangeStart?: string
  customRangeEnd?: string
  accountFilter?: string
}): string {
  const timeframe = dashboardTimeframeCapsuleLabel({
    timeframe: options.timeFilter,
    selectedDate: options.selectedDate ?? "",
    customRangeStart: options.customRangeStart,
    customRangeEnd: options.customRangeEnd,
  })
  const account =
    !options.accountFilter || options.accountFilter === "all"
      ? "All accounts"
      : "Filtered accounts"
  return `${timeframe} · ${account}`
}
