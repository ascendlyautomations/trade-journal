import type { ProfileTab } from "@/app/components/profile/ProfileTabs"

/** Left-to-right order — matches ``ProfileTabs`` strip. */
export const PROFILE_TAB_STRIP_ORDER: readonly ProfileTab[] = [
  "trades",
  "reels",
  "posts",
  "calendar",
  "stats",
  "achievements",
] as const

export function adjacentProfileTab(
  tab: ProfileTab,
  offset: number
): ProfileTab | null {
  return adjacentTabInOrder(PROFILE_TAB_STRIP_ORDER, tab, offset)
}

/**
 * Phone-only Profile section order — matches native
 * Trades → Posts → Clips → Stats → Achievements.
 * Desktop ``PROFILE_TAB_STRIP_ORDER`` (including Calendar) is unchanged.
 */
export const MOBILE_WEB_PROFILE_TAB_ORDER: readonly ProfileTab[] = [
  "trades",
  "posts",
  "reels",
  "stats",
  "achievements",
] as const

export function adjacentMobileWebProfileTab(
  tab: ProfileTab,
  offset: number
): ProfileTab | null {
  return adjacentTabInOrder(MOBILE_WEB_PROFILE_TAB_ORDER, tab, offset)
}

function adjacentTabInOrder(
  order: readonly ProfileTab[],
  tab: ProfileTab,
  offset: number
): ProfileTab | null {
  if (offset === 0) return null
  const index = order.indexOf(tab)
  if (index < 0) return null
  const target = index + offset
  if (target < 0 || target >= order.length) return null
  return order[target] ?? null
}
