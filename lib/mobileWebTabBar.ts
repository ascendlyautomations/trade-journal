import { CREATE_ROUTE, isCreateHubPath } from "./createRoutes.ts"
import { isAppAddTradePath } from "./addTradePath.ts"
import { resolveMobileWebCreateChrome } from "./mobileWebCreateChrome.ts"
import { getMobileWebTradeTitle } from "./mobileWebTradeTitle.ts"

export type MobileWebTabId = "home" | "feed" | "create" | "messages" | "profile"

export const MOBILE_WEB_TAB_BAR_HEIGHT_PX = 49

/** Phone-only create sheet — dispatched by the tab bar, handled by CreateHubMenu. */
export const MOBILE_WEB_OPEN_CREATE_EVENT = "tt-mobile-web-open-create"

/** Phone navbar compose — handled by the messages inbox. */
export const MOBILE_WEB_OPEN_COMPOSE_EVENT = "tt-mobile-web-open-compose"

/** Hides the 44px app navbar on conversation threads (in-page header is the bar). */
export const MOBILE_WEB_HIDE_NAVBAR_CLASS = "tt-mobile-web-hide-navbar"

export function openMobileWebCreateSheet() {
  if (typeof window === "undefined") return
  window.dispatchEvent(new Event(MOBILE_WEB_OPEN_CREATE_EVENT))
}

export function openMobileWebCompose() {
  if (typeof window === "undefined") return
  window.dispatchEvent(new Event(MOBILE_WEB_OPEN_COMPOSE_EVENT))
}

export function isMobileWebMessageThreadPath(pathname: string): boolean {
  return Boolean(pathname.match(/^\/messages\/([^/]+)\/?$/)?.[1]?.trim())
}

export type MobileWebNavLeading = "back" | "calendar" | "settings" | null

export type MobileWebNavChrome = {
  title: string
  backHref: string | null
  leading: MobileWebNavLeading
  showBell: boolean
  showCompose: boolean
  showExplore: boolean
}

/** Same-origin in-app back. Deep links and refresh fall through to `backHref`. */
export function shouldUseMobileWebHistoryBack(
  referrer: string,
  origin: string,
  historyLength: number
): boolean {
  if (historyLength <= 1 || !referrer) return false
  try {
    return new URL(referrer).origin === origin
  } catch {
    return false
  }
}

/**
 * Phone-only 44px navigation chrome. Tab roots get a title (no back).
 * Secondary pages get back + title. Conversation threads return null —
 * the in-page thread header is the only bar.
 */
export function resolveMobileWebNavChrome(
  pathname: string,
  search = ""
): MobileWebNavChrome | null {
  if (isMobileWebMessageThreadPath(pathname)) return null
  const createChrome = resolveMobileWebCreateChrome(pathname)
  if (createChrome) {
    return {
      title: createChrome.title,
      backHref: createChrome.backHref,
      leading: "back",
      showBell: false,
      showCompose: false,
      showExplore: false,
    }
  }
  const secondary = resolveMobileWebPageHeader(pathname, search)
  if (secondary) {
    return {
      title: secondary.title,
      backHref: secondary.backHref,
      leading: "back",
      showBell: false,
      showCompose: false,
      showExplore: false,
    }
  }
  if (pathname === "/dashboard" || pathname.startsWith("/dashboard/")) {
    return {
      title: "Dashboard",
      backHref: null,
      leading: "calendar",
      showBell: true,
      showCompose: false,
      showExplore: false,
    }
  }
  if (pathname === "/feed" || pathname.startsWith("/feed/")) {
    return {
      title: "Feed",
      backHref: null,
      leading: null,
      showBell: false,
      showCompose: false,
      showExplore: true,
    }
  }
  if (pathname === "/messages") {
    return {
      title: "Messages",
      backHref: null,
      leading: "settings",
      showBell: false,
      showCompose: true,
      showExplore: false,
    }
  }
  if (pathname === "/profile" || pathname.startsWith("/profile/")) {
    return {
      title: "Profile",
      backHref: null,
      leading: null,
      showBell: false,
      showCompose: false,
      showExplore: false,
    }
  }
  return null
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
  hasSession: boolean,
  search = ""
): boolean {
  if (!hasSession) return false
  if (pathname === "/") return false
  if (shouldHideMobileWebTabBar(pathname, search)) return false
  return true
}

function isSingleSegmentDetail(pathname: string, root: string): boolean {
  const match = pathname.match(new RegExp(`^/${root}/([^/]+)/?$`))
  return Boolean(match?.[1]?.trim())
}

/**
 * Native `.toolbar(.hidden, for: .tabBar)` counterparts.
 * Inbox, tab roots, Calendar, Trades list, Activity, Explore, Settings stay visible.
 */
export function shouldHideMobileWebTabBar(
  pathname: string,
  search = ""
): boolean {
  const match = pathname.match(/^\/messages\/([^/]+)\/?$/)
  if (match?.[1]?.trim()) return true
  if (pathname === "/leaderboard" || pathname.startsWith("/leaderboard/")) {
    return true
  }
  if (pathname === "/withdrawals" || pathname.startsWith("/withdrawals/")) {
    return true
  }
  if (pathname.startsWith("/room/")) return true
  if (pathname === "/community" || pathname.startsWith("/community/")) {
    const query = search.startsWith("?") ? search.slice(1) : search
    return Boolean(new URLSearchParams(query).get("room")?.trim())
  }
  if (isSingleSegmentDetail(pathname, "trade")) return true
  if (isSingleSegmentDetail(pathname, "post")) return true
  if (isSingleSegmentDetail(pathname, "reel")) return true
  if (pathname === "/backtest" || pathname.startsWith("/backtest/")) return true
  if (
    pathname === "/psychology/analytics" ||
    pathname.startsWith("/psychology/analytics/")
  ) {
    return true
  }
  if (
    pathname === "/psychology/coach" ||
    pathname.startsWith("/psychology/coach/")
  ) {
    return true
  }
  if (
    pathname === "/check-in-history" ||
    pathname.startsWith("/check-in-history/")
  ) {
    return true
  }
  if (pathname === "/analytics/propfirm" || pathname.startsWith("/analytics/")) {
    return true
  }
  if (pathname === "/suggestions" || pathname.startsWith("/suggestions/")) {
    return true
  }
  return false
}

/** Secondary pages that lack a visible phone title today. */
export const MOBILE_WEB_PAGE_HEADERS: Record<
  string,
  { title: string; backHref: string }
> = {
  "/calendar": { title: "Calendar", backHref: "/dashboard" },
  "/trades": { title: "Trades", backHref: "/dashboard" },
  "/explore": { title: "Explore", backHref: "/feed" },
  "/notifications": { title: "Activity", backHref: "/dashboard" },
  "/leaderboard": { title: "Leaderboards", backHref: "/explore" },
  "/achievements": { title: "Achievements", backHref: "/dashboard" },
  "/withdrawals": { title: "Withdrawals", backHref: "/dashboard" },
  "/psychology/analytics": {
    title: "Psychology Analytics",
    backHref: "/dashboard",
  },
  "/settings": { title: "Settings", backHref: "/dashboard" },
  "/analyst": { title: "AI Analyst", backHref: "/dashboard" },
  "/streaks": { title: "Streaks", backHref: "/dashboard" },
  "/community": { title: "Trade Rooms", backHref: "/explore" },
  "/analytics/propfirm": { title: "Prop Firm", backHref: "/dashboard" },
  "/prop-firm-expenses": { title: "Expense Tracker", backHref: "/settings" },
  "/psychology/coach": {
    title: "Psychology Coach",
    backHref: "/psychology/analytics",
  },
  "/check-in-history": { title: "Check-In History", backHref: "/dashboard" },
  "/vault": { title: "Vault", backHref: "/dashboard" },
  "/referrals": { title: "Referrals", backHref: "/dashboard" },
  "/affiliate": { title: "Affiliate", backHref: "/dashboard" },
  "/help": { title: "Help Center", backHref: "/dashboard" },
  "/suggestions": { title: "Suggestions", backHref: "/dashboard" },
  "/import": { title: "Import CSV", backHref: "/trades" },
  "/scorecard": { title: "Trading Scorecard", backHref: "/dashboard" },
  "/feature-requests": { title: "Feature Requests", backHref: "/dashboard" },
}

export const MOBILE_WEB_SOCIAL_DETAIL_CLASS = "tt-mobile-web-social-detail"

export function setMobileWebSocialDetail(active: boolean) {
  if (typeof document === "undefined") return
  document.documentElement.classList.toggle(
    MOBILE_WEB_SOCIAL_DETAIL_CLASS,
    active
  )
}

export function resolveMobileWebPageHeader(
  pathname: string,
  search = ""
): { title: string; backHref: string } | null {
  if (pathname === "/community" || pathname.startsWith("/community/")) {
    const query = search.startsWith("?") ? search.slice(1) : search
    if (new URLSearchParams(query).get("room")?.trim()) {
      return { title: "Trade Room", backHref: "/community" }
    }
  }
  if (MOBILE_WEB_PAGE_HEADERS[pathname]) {
    return MOBILE_WEB_PAGE_HEADERS[pathname]
  }
  if (pathname.startsWith("/room/")) {
    return { title: "Trade Room", backHref: "/community" }
  }
  if (pathname.startsWith("/withdrawals/")) {
    return { title: "Withdrawal", backHref: "/withdrawals" }
  }
  if (pathname.startsWith("/check-in-history/")) {
    return { title: "Check-In", backHref: "/check-in-history" }
  }
  if (pathname.startsWith("/affiliate/")) {
    return { title: "Affiliate", backHref: "/dashboard" }
  }
  if (pathname.startsWith("/help/")) {
    return { title: "Help Center", backHref: "/dashboard" }
  }
  if (pathname.startsWith("/create/")) {
    return null
  }
  if (isSingleSegmentDetail(pathname, "trade")) {
    return {
      title: getMobileWebTradeTitle() ?? "Trade",
      backHref: "/trades",
    }
  }
  if (isSingleSegmentDetail(pathname, "reel")) {
    return { title: "Clip", backHref: "/feed" }
  }
  if (pathname === "/backtest" || pathname.startsWith("/backtest/")) {
    return { title: "Backtest Lab", backHref: "/dashboard" }
  }
  if (isSingleSegmentDetail(pathname, "post")) {
    return { title: "Post", backHref: "/feed" }
  }
  return null
}
