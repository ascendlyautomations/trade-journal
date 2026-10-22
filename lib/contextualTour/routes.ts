import type { ContextualTourSurface } from "./types"

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
  }
}
