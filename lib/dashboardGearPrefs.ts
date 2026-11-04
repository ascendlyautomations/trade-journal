import type { DashboardGearPersistedPrefs } from "@/app/components/dashboard/dashboardGearTypes"
import { DASHBOARD_DEFAULT_TIME_FILTER } from "@/lib/dashboardInitialTimeframe"

export const DASHBOARD_GEAR_PREFS_KEY = "tradetrax_dashboard_prefs_v1"

export function loadDashboardGearPrefs(): Partial<DashboardGearPersistedPrefs> | null {
  if (typeof window === "undefined") return null
  try {
    const s = window.localStorage.getItem(DASHBOARD_GEAR_PREFS_KEY)
    if (!s) return null
    const p = JSON.parse(s) as Partial<DashboardGearPersistedPrefs>
    return p && typeof p === "object" ? p : null
  } catch {
    return null
  }
}

export function resolveDashboardGearDefaults(
  patch?: Partial<DashboardGearPersistedPrefs> | null
): DashboardGearPersistedPrefs {
  const existing = patch ?? loadDashboardGearPrefs()
  return {
    timeFilter: existing?.timeFilter ?? DASHBOARD_DEFAULT_TIME_FILTER,
    hasUserSelectedTimeframe: existing?.hasUserSelectedTimeframe,
    accountFilter: existing?.accountFilter ?? "all",
    accountTypeFilter: existing?.accountTypeFilter ?? "all",
    showPublicOnly: existing?.showPublicOnly ?? false,
    showEquity: existing?.showEquity ?? true,
    showDrawdown: existing?.showDrawdown ?? true,
    showInsights: existing?.showInsights ?? true,
    showSessions: existing?.showSessions ?? true,
    showBestSetup: existing?.showBestSetup ?? true,
    showWorstSetup: existing?.showWorstSetup ?? true,
    showWarnings: existing?.showWarnings ?? true,
  }
}
