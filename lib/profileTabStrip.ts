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
  if (offset === 0) return null
  const index = PROFILE_TAB_STRIP_ORDER.indexOf(tab)
  if (index < 0) return null
  const target = index + offset
  if (target < 0 || target >= PROFILE_TAB_STRIP_ORDER.length) return null
  return PROFILE_TAB_STRIP_ORDER[target] ?? null
}
