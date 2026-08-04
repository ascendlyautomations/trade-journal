/** Shared Dashboard timeframe labels — keep TradeFilterBar + native sheet in sync. */

export const DASHBOARD_ALL_TIMEFRAME_LABEL = "All Time"

export const DASHBOARD_TF_LABEL_FROM_VALUE: Record<string, string> = {
  all: DASHBOARD_ALL_TIMEFRAME_LABEL,
  daily: "Today",
  weekly: "This Week",
  monthly: "This Month",
  yearly: "This Year",
  custom: "Custom",
}

export const DASHBOARD_PRESET_TIMEFRAME_LABELS = [
  DASHBOARD_ALL_TIMEFRAME_LABEL,
  "Today",
  "This Week",
  "This Month",
  "This Year",
] as const

export const DASHBOARD_PRESET_LABEL_TO_VALUE: Record<string, string> = {
  [DASHBOARD_ALL_TIMEFRAME_LABEL]: "all",
  Today: "daily",
  "This Week": "weekly",
  "This Month": "monthly",
  "This Year": "yearly",
}

/** Capsule / compact label for the active timeframe filter. */
export function dashboardTimeframeCapsuleLabel(options: {
  timeframe: string
  selectedDate: string
  customRangeStart?: string
  customRangeEnd?: string
}): string {
  const { timeframe, selectedDate, customRangeStart, customRangeEnd } = options
  if (selectedDate) {
    return selectedDate
  }
  if (timeframe === "custom" && customRangeStart && customRangeEnd) {
    return `${customRangeStart} – ${customRangeEnd}`
  }
  if (timeframe === "custom") return "Custom"
  return DASHBOARD_TF_LABEL_FROM_VALUE[timeframe] ?? DASHBOARD_ALL_TIMEFRAME_LABEL
}
