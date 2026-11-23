import { PRODUCT_ANALYTICS_SCREENS, type ProductAnalyticsScreenId } from "./constants"
import { isAppAddTradePath } from "@/lib/addTradePath"
import { isAppCalendarPath } from "@/lib/calendarPath"
import { isAppDashboardPath } from "@/lib/dashboardPath"
import { isAppFeedPath } from "@/lib/feedPath"
import { isAppMessagesInboxPath } from "@/lib/messagesPath"
import { isAppCommunityPath } from "@/lib/communityPath"
import { isAppTradesPath } from "@/lib/tradesPath"
import { isDmConversationPath } from "@/lib/messageRoutes"

/** Maps authenticated app pathname → stable screen id (no PII). */
export function screenIdFromPathname(pathname: string): ProductAnalyticsScreenId {
  const path = String(pathname ?? "").split("?")[0] ?? ""
  if (!path || path === "/") return PRODUCT_ANALYTICS_SCREENS.unknown
  if (isAppDashboardPath(path)) return PRODUCT_ANALYTICS_SCREENS.dashboard
  if (path.startsWith("/analytics")) return PRODUCT_ANALYTICS_SCREENS.analytics
  if (isAppCalendarPath(path)) return PRODUCT_ANALYTICS_SCREENS.calendar
  if (isAppTradesPath(path)) {
    if (path.startsWith("/trade/") || path.startsWith("/trades/")) {
      return PRODUCT_ANALYTICS_SCREENS.tradeDetail
    }
    return PRODUCT_ANALYTICS_SCREENS.trades
  }
  if (path.startsWith("/trade/")) return PRODUCT_ANALYTICS_SCREENS.tradeDetail
  if (isAppFeedPath(path)) return PRODUCT_ANALYTICS_SCREENS.feed
  if (isDmConversationPath(path)) return PRODUCT_ANALYTICS_SCREENS.messageThread
  if (isAppMessagesInboxPath(path)) return PRODUCT_ANALYTICS_SCREENS.messages
  if (isAppCommunityPath(path)) return PRODUCT_ANALYTICS_SCREENS.tradeRooms
  if (path.startsWith("/trade-rooms/")) return PRODUCT_ANALYTICS_SCREENS.tradeRoom
  if (path.startsWith("/explore")) return PRODUCT_ANALYTICS_SCREENS.explore
  if (path.startsWith("/settings")) return PRODUCT_ANALYTICS_SCREENS.settings
  if (isAppAddTradePath(path)) return PRODUCT_ANALYTICS_SCREENS.addTrade
  if (path.startsWith("/admin")) return PRODUCT_ANALYTICS_SCREENS.admin
  if (path.startsWith("/profile/")) return PRODUCT_ANALYTICS_SCREENS.profileOther
  if (path.startsWith("/onboarding")) return PRODUCT_ANALYTICS_SCREENS.onboarding
  if (path.startsWith("/ai") || path.includes("analyst")) {
    return PRODUCT_ANALYTICS_SCREENS.aiAnalyst
  }
  if (path.includes("broker") && path.includes("integration")) {
    return PRODUCT_ANALYTICS_SCREENS.brokerIntegrations
  }
  const profileMatch = /^\/([^/]+)\/?$/.exec(path)
  if (profileMatch) {
    const seg = profileMatch[1]
    const reserved = new Set([
      "dashboard",
      "feed",
      "trades",
      "calendar",
      "messages",
      "settings",
      "explore",
      "login",
      "signup",
      "admin",
    ])
    if (seg && !reserved.has(seg)) {
      return PRODUCT_ANALYTICS_SCREENS.profileOther
    }
  }
  return PRODUCT_ANALYTICS_SCREENS.unknown
}

export function featureKeyFromScreen(
  screenId: ProductAnalyticsScreenId
): string | null {
  switch (screenId) {
    case PRODUCT_ANALYTICS_SCREENS.dashboard:
      return "dashboard"
    case PRODUCT_ANALYTICS_SCREENS.analytics:
      return "analytics"
    case PRODUCT_ANALYTICS_SCREENS.trades:
    case PRODUCT_ANALYTICS_SCREENS.tradeDetail:
      return "trades"
    case PRODUCT_ANALYTICS_SCREENS.feed:
      return "feed"
    case PRODUCT_ANALYTICS_SCREENS.messages:
    case PRODUCT_ANALYTICS_SCREENS.messageThread:
      return "messages"
    case PRODUCT_ANALYTICS_SCREENS.tradeRooms:
    case PRODUCT_ANALYTICS_SCREENS.tradeRoom:
      return "trade_rooms"
    case PRODUCT_ANALYTICS_SCREENS.aiAnalyst:
      return "ai_analyst"
    case PRODUCT_ANALYTICS_SCREENS.brokerIntegrations:
      return "broker_integrations"
    case PRODUCT_ANALYTICS_SCREENS.calendar:
      return "calendar"
    case PRODUCT_ANALYTICS_SCREENS.explore:
      return "explore"
    case PRODUCT_ANALYTICS_SCREENS.addTrade:
      return "add_trade"
    case PRODUCT_ANALYTICS_SCREENS.settings:
      return "settings"
    default:
      return null
  }
}