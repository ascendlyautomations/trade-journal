import type { ExploreProfile } from "./exploreDiscover.ts"

export const EXPLORE_SUGGESTED_INITIAL_ROWS = 4

export function hasExploreProfileAvatar(
  avatarUrl: string | null | undefined
): boolean {
  return (avatarUrl?.trim() ?? "").length > 0
}

/** Stable partition: avatars first, preserve prior order inside each group. */
export function orderExploreSuggestedTraders(
  profiles: ExploreProfile[]
): ExploreProfile[] {
  const withAvatar: ExploreProfile[] = []
  const withoutAvatar: ExploreProfile[] = []

  for (const profile of profiles) {
    if (hasExploreProfileAvatar(profile.avatar_url)) {
      withAvatar.push(profile)
    } else {
      withoutAvatar.push(profile)
    }
  }

  return [...withAvatar, ...withoutAvatar]
}

export function exploreGridColumnCount(viewportWidth: number): number {
  if (viewportWidth >= 1024) return 3
  if (viewportWidth >= 640) return 2
  return 1
}

export function exploreSuggestedVisibleBatch(columnCount: number): number {
  return Math.max(1, columnCount) * EXPLORE_SUGGESTED_INITIAL_ROWS
}
