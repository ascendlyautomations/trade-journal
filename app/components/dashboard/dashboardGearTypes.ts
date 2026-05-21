export type DashboardGearPersistedPrefs = {
  timeFilter: string
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

export type GearDraftState = DashboardGearPersistedPrefs & {
  drawdownLimit: string
}
