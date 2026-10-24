export type ContextualTourId = "dashboard"

export type ContextualTourSurface =
  | "dashboard"
  | "feed"
  | "profile"
  | "settings"
  | "payouts"
  | "expenseTracker"

export type ContextualTourStepRole =
  | "spotlight"
  | "narration"
  | "sectionContinue"
  | "finish"

export type ContextualTourTargetId =
  | "dashboardAccountAndDates"
  | "dashboardPerformance"
  | "dashboardTrades"
  | "dashboardReports"
  | "dashboardWithdrawals"
  | "dashboardCalendar"
  | "dashboardNotifications"
  | "feedContentFilters"
  | "feedTradeRooms"
  | "feedExplore"
  | "profileIdentity"
  | "profileTradeRoom"
  | "settingsBroker"
  | "settingsAppearance"
  | "payoutsHistory"
  | "expenseTrackerAdd"
  | "expenseTrackerIncome"
  | "expenseTrackerAnalytics"
  | "expenseTrackerExport"

export type ContextualTourStep = {
  target?: ContextualTourTargetId
  title: string
  message: string
  surface: ContextualTourSurface
  role?: ContextualTourStepRole
  presentsIfUnmeasured?: boolean
}

export type ContextualTourDefinition = {
  id: ContextualTourId
  version: number
  steps: ContextualTourStep[]
}

export type ContextualTourPhase = "idle" | "measuring" | "presenting"

export function stepRole(step: ContextualTourStep): ContextualTourStepRole {
  return step.role ?? "spotlight"
}

export function countsTowardProgress(role: ContextualTourStepRole): boolean {
  switch (role) {
    case "spotlight":
    case "narration":
    case "finish":
      return true
    case "sectionContinue":
      return false
  }
}
