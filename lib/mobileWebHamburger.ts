import { isCreateHubPath } from "./createRoutes.ts"
import { isAppAddTradePath } from "./addTradePath.ts"

export type MobileWebHamburgerSection =
  | "create"
  | "analytics"
  | "community"
  | "account"
  | "support"

const ANALYTICS_PREFIXES = [
  "/calendar",
  "/analytics",
  "/backtest",
  "/streaks",
  "/achievements",
  "/analyst",
] as const

const COMMUNITY_PREFIXES = [
  "/community",
  "/trade-rooms",
  "/leaderboard",
  "/explore",
  "/room/",
] as const

const ACCOUNT_PREFIXES = [
  "/settings",
  "/notifications",
  "/referrals",
  "/affiliate",
  "/payouts",
] as const

const SUPPORT_PREFIXES = [
  "/help",
  "/privacy",
  "/terms",
  "/feature-requests",
] as const

function matchesPrefix(pathname: string, prefixes: readonly string[]): boolean {
  return prefixes.some((prefix) =>
    prefix.endsWith("/")
      ? pathname.startsWith(prefix)
      : pathname === prefix || pathname.startsWith(`${prefix}/`)
  )
}

/**
 * Which hamburger accordion should auto-expand for the current route.
 * Primary desktop destinations (Dashboard, Trades, Feed, Profile, Messages)
 * return null so they stay top-level.
 */
export function resolveMobileWebHamburgerSection(
  pathname: string
): MobileWebHamburgerSection | null {
  if (isCreateHubPath(pathname) || isAppAddTradePath(pathname)) {
    return "create"
  }
  if (matchesPrefix(pathname, ANALYTICS_PREFIXES)) return "analytics"
  if (matchesPrefix(pathname, COMMUNITY_PREFIXES)) return "community"
  if (matchesPrefix(pathname, ACCOUNT_PREFIXES)) return "account"
  if (matchesPrefix(pathname, SUPPORT_PREFIXES)) return "support"
  return null
}
