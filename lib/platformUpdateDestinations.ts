/** Stable destination ids for admin updates + broadcast deep links (web + iOS). */

export const PLATFORM_UPDATE_DESTINATIONS = [
  "whats_new",
  "dashboard",
  "feed",
  "trades",
  "calendar",
  "analytics",
  "profile",
  "messages",
  "trade_rooms",
  "broker_integrations",
  "subscription",
  "settings",
] as const

export type PlatformUpdateDestinationId =
  (typeof PLATFORM_UPDATE_DESTINATIONS)[number]

export const PLATFORM_UPDATE_DESTINATION_LABELS: Record<
  PlatformUpdateDestinationId,
  string
> = {
  whats_new: "What's New",
  dashboard: "Dashboard",
  feed: "Feed",
  trades: "Trades",
  calendar: "Calendar",
  analytics: "Analytics",
  profile: "Profile",
  messages: "Messages",
  trade_rooms: "Trade Rooms",
  broker_integrations: "Broker Integrations",
  subscription: "TraxPro / Subscription",
  settings: "Settings",
}

export function isPlatformUpdateDestinationId(
  value: string | null | undefined
): value is PlatformUpdateDestinationId {
  if (!value?.trim()) return false
  return (PLATFORM_UPDATE_DESTINATIONS as readonly string[]).includes(
    value.trim()
  )
}

/** Authoritative web + universal-link href for push payloads and in-app links. */
export function platformUpdateDestinationHref(
  destination: PlatformUpdateDestinationId
): string {
  switch (destination) {
    case "whats_new":
      return "/whats-new"
    case "dashboard":
      return "/dashboard"
    case "feed":
      return "/feed"
    case "trades":
      return "/dashboard/trades"
    case "calendar":
      return "/calendar"
    case "analytics":
      return "/dashboard"
    case "profile":
      return "/settings/profile"
    case "messages":
      return "/messages"
    case "trade_rooms":
      return "/community"
    case "broker_integrations":
      return "/settings/broker-integrations"
    case "subscription":
      return "/settings/subscription"
    case "settings":
      return "/settings"
    default:
      return "/whats-new"
  }
}

export const PLATFORM_UPDATE_CATEGORIES = [
  "announcement",
  "new_feature",
  "improvement",
  "fix",
  "maintenance",
] as const

export type PlatformUpdateCategoryId =
  (typeof PLATFORM_UPDATE_CATEGORIES)[number]

export const PLATFORM_UPDATE_CATEGORY_LABELS: Record<
  PlatformUpdateCategoryId,
  string
> = {
  announcement: "Announcement",
  new_feature: "New Feature",
  improvement: "Improvement",
  fix: "Fix",
  maintenance: "Maintenance",
}

export function isPlatformUpdateCategoryId(
  value: string | null | undefined
): value is PlatformUpdateCategoryId {
  if (!value?.trim()) return false
  return (PLATFORM_UPDATE_CATEGORIES as readonly string[]).includes(
    value.trim()
  )
}
