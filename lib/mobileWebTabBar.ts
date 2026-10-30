import { CREATE_ROUTE, isCreateHubPath } from "./createRoutes.ts"
import { isAppAddTradePath } from "./addTradePath.ts"

export type MobileWebTabId = "home" | "feed" | "create" | "messages" | "profile"

export const MOBILE_WEB_TAB_BAR_HEIGHT_PX = 49

/** Phone-only create sheet — dispatched by the tab bar, handled by CreateHubMenu. */
export const MOBILE_WEB_OPEN_CREATE_EVENT = "tt-mobile-web-open-create"

export function openMobileWebCreateSheet() {
  if (typeof window === "undefined") return
  window.dispatchEvent(new Event(MOBILE_WEB_OPEN_CREATE_EVENT))
}

export function isMobileWebTabRootPath(pathname: string): boolean {
  return (
    pathname === "/dashboard" ||
    pathname.startsWith("/dashboard/") ||
    pathname === "/feed" ||
    pathname.startsWith("/feed/") ||
    pathname === "/messages" ||
    pathname.startsWith("/messages/") ||
    pathname === "/profile" ||
    pathname.startsWith("/profile/") ||
    isCreateHubPath(pathname) ||
    isAppAddTradePath(pathname)
  )
}

/**
 * Which tab is selected. Secondary routes (Calendar, Trades, …) return null
 * so no tab appears active — same as native pushes off Home/Feed.
 */
export function resolveMobileWebActiveTab(
  pathname: string,
  profileHref: string | null,
  createSheetOpen = false
): MobileWebTabId | null {
  if (
    createSheetOpen ||
    isCreateHubPath(pathname) ||
    isAppAddTradePath(pathname) ||
    pathname === CREATE_ROUTE.addTrade
  ) {
    return "create"
  }
  if (pathname === "/dashboard" || pathname.startsWith("/dashboard/")) {
    return "home"
  }
  if (pathname === "/feed" || pathname.startsWith("/feed/")) {
    return "feed"
  }
  if (pathname === "/messages" || pathname.startsWith("/messages/")) {
    return "messages"
  }
  if (profileHref) {
    if (pathname === profileHref || pathname.startsWith(`${profileHref}/`)) {
      return "profile"
    }
  }
  if (pathname === "/profile" || pathname.startsWith("/profile/")) {
    return "profile"
  }
  return null
}

export function shouldMountMobileWebTabBar(
  pathname: string,
  hasSession: boolean
): boolean {
  if (!hasSession) return false
  if (pathname === "/") return false
  return true
}

/** Secondary pages that lack a visible phone title today. */
export const MOBILE_WEB_PAGE_HEADERS: Record<
  string,
  { title: string; backHref: string }
> = {
  "/calendar": { title: "Calendar", backHref: "/dashboard" },
  "/trades": { title: "Trades", backHref: "/dashboard" },
  "/explore": { title: "Explore", backHref: "/feed" },
}

export function resolveMobileWebPageHeader(
  pathname: string
): { title: string; backHref: string } | null {
  if (MOBILE_WEB_PAGE_HEADERS[pathname]) {
    return MOBILE_WEB_PAGE_HEADERS[pathname]
  }
  if (pathname.startsWith("/room/")) {
    return { title: "Trade Room", backHref: "/community" }
  }
  if (pathname.startsWith("/withdrawals/")) {
    return { title: "Withdrawal", backHref: "/withdrawals" }
  }
  return null
}
