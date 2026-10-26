export type DashboardGearPersistedPrefs = {
  timeFilter: string
  /** When true, automatic 30D→90D→1Y→All fallback must not run. */
  hasUserSelectedTimeframe?: boolean
  accountFilter: string
  accountTypeFilter: string
  showPublicOnly: boolean
  showEquity: boolean
  showDrawdown: boolean
  showInsights: boolean
  showSessions: boolean
  showBestSetup: boolean
  showWorstSetup: boolean
  showWarnings: boolean
}

export type LivePersonalDrawdownGearType = "fixed" | "trailing"

export type GearDraftState = DashboardGearPersistedPrefs & {
  drawdownLimit: string
  /** When a single Live account is selected, configure per-account drawdown. */
  livePersonalDrawdown: boolean
  liveDrawdownType: LivePersonalDrawdownGearType
}
