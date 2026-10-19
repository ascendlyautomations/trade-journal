import type { PsychologyInsightCategory } from "./reports/types.ts"

/** iOS `DashboardViewModel.psychologySectionID(for:)`. */
export function psychologySectionIdForCategory(
  category: PsychologyInsightCategory
): string {
  switch (category) {
    case "sleep":
      return "sleep"
    case "mentalState":
      return "mentalState"
    case "conviction":
      return "conviction"
    case "discipline":
      return "discipline"
    case "emotion":
      return "emotion"
    case "afterLosses":
      return "afterLosses"
    case "tradeFrequency":
      return "tradeFrequency"
    case "combined":
      return "combined"
  }
}
