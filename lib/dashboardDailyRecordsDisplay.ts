export const DASHBOARD_ONLY_ONE_TRADING_DAY_TOOLTIP = "Only one trading day"

/** Stat `positive` prop: green / red / neutral (undefined). */
export function dashboardSignedPnlPositiveFlag(
  value: number
): boolean | undefined {
  if (value > 0) return true
  if (value < 0) return false
  return undefined
}

export function dashboardSignedPnlTailwindClass(value: number): string {
  if (value > 0) return "text-green-400"
  if (value < 0) return "text-red-400"
  return "text-white"
}

export function dashboardSignedPnlKpiClass(value: number): string {
  if (value > 0) {
    return "text-lg font-semibold tabular-nums text-green-400"
  }
  if (value < 0) {
    return "text-lg font-semibold tabular-nums text-red-400"
  }
  return "text-lg font-semibold tabular-nums tt-dash-value"
}

export type DashboardWorstDayDisplay = {
  displayValue: string
  /** When null, use neutral styling (single trading day). */
  toneValue: number | null
  valueTitle?: string
}

export function formatDashboardWorstDayDisplay(
  periodTradingDayCount: number,
  worstDay: number,
  formatMoney: (amount: number) => string
): DashboardWorstDayDisplay {
  if (periodTradingDayCount === 1) {
    return {
      displayValue: "—",
      toneValue: null,
      valueTitle: DASHBOARD_ONLY_ONE_TRADING_DAY_TOOLTIP,
    }
  }
  return {
    displayValue: formatMoney(worstDay),
    toneValue: worstDay,
  }
}
