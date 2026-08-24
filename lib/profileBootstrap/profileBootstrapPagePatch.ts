import type { ProfileBootstrapLoadResult } from "./profileBootstrapRepository.ts"

export function profileSessionPayloadFromBootstrap(
  boot: ProfileBootstrapLoadResult,
  pageSize: number
) {
  return {
    profile: boot.profile!,
    room: null,
    roomReady: false,
    followersCount: boot.followersCount,
    followingCount: boot.followingCount,
    isFollowing: boot.isFollowing,
    isRequested: boot.isRequested,
    followsYou: boot.followsYou,
    allTrades: boot.trades,
    wallPosts: [] as unknown[],
    visibleTradeCount: boot.trades.length || pageSize,
    tradeHasMore: boot.tradeHasMore,
    tradesReady: boot.canViewTrades,
    bootstrapPublicStats: boot.publicStats,
    bootstrapSectionCounts: boot.sectionCounts,
    summaryReady: boot.publicStats != null,
    scrollY: 0,
  }
}

export function previewProfileRowFromHeaderPreview(preview: {
  id: string
  username?: string | null
  name?: string | null
  avatar_url?: string | null
  is_private?: boolean | null
}): Record<string, unknown> {
  return {
    id: preview.id,
    username: preview.username ?? null,
    name: preview.name ?? preview.username ?? null,
    avatar_url: preview.avatar_url ?? null,
    is_private: preview.is_private ?? null,
  }
}
