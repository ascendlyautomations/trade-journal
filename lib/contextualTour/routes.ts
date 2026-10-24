import type { ContextualTourStep } from "./types"
import type { ContextualTourSurface } from "./types"
import { stepRole } from "./types"

export function routeForTourSurface(
  surface: ContextualTourSurface,
  userId: string
): string {
  switch (surface) {
    case "dashboard":
      return "/dashboard"
    case "feed":
      return "/feed"
    case "profile":
      return `/profile/${userId}`
    case "settings":
      return "/settings"
    case "payouts":
      return "/withdrawals"
    case "expenseTracker":
      return "/prop-firm-expenses"
  }
}

/** Some steps open a dedicated route (not only the surface default). */
export function routeForTourStep(
  step: ContextualTourStep,
  userId: string
): string {
  switch (step.target) {
    case "feedTradeRooms":
      return "/community"
    case "feedExplore":
      return "/explore"
    case "payoutsHistory":
      return "/withdrawals"
    case "expenseTrackerAdd":
    case "expenseTrackerIncome":
    case "expenseTrackerAnalytics":
    case "expenseTrackerExport":
      return "/prop-firm-expenses"
    default:
      return routeForTourSurface(step.surface, userId)
  }
}

export function pathnameMatchesTourSurface(
  pathname: string,
  surface: ContextualTourSurface,
  userId: string
): boolean {
  switch (surface) {
    case "dashboard":
      return pathname === "/dashboard" || pathname.startsWith("/dashboard/")
    case "feed":
      return pathname === "/feed" || pathname.startsWith("/feed/")
    case "profile":
      return pathname === `/profile/${userId}`
    case "settings":
      return pathname === "/settings" || pathname.startsWith("/settings/")
    case "payouts":
      return pathname === "/withdrawals"
    case "expenseTracker":
      return pathname === "/prop-firm-expenses"
  }
}

export function pathnameMatchesTourStep(
  pathname: string,
  step: ContextualTourStep,
  userId: string
): boolean {
  if (stepRole(step) === "sectionContinue") return true
  const route = routeForTourStep(step, userId)
  if (route === "/community") {
    return pathname === "/community" || pathname.startsWith("/room/")
  }
  if (route === "/explore") {
    return pathname === "/explore" || pathname.startsWith("/explore/")
  }
  if (route === "/withdrawals" || route === "/prop-firm-expenses") {
    return pathname === route
  }
  if (route === "/feed") {
    return pathnameMatchesTourSurface(pathname, "feed", userId)
  }
  if (route.startsWith("/profile/")) {
    return pathname === route
  }
  return pathname === route || pathname.startsWith(`${route}/`)
}
