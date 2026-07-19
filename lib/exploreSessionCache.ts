import type { TradeForLeaderboard } from "@/lib/leaderboardChart"
import type { ExploreProfile, ExploreTopView } from "@/lib/exploreDiscover"

const DEFAULT_STALE_MS = 5 * 60 * 1000

export type ExploreSessionSnapshot = {
  currentUserId: string | null
  profiles: ExploreProfile[]
  followingIds: string[]
  requestedIds: string[]
  followsYouIds: string[]
  tradesByView: Partial<Record<ExploreTopView, TradeForLeaderboard[]>>
  topView: ExploreTopView
  scrollY: number
  fetchedAt: number
}

let session: ExploreSessionSnapshot | null = null

function exploreCacheUserKey(userId: string | null | undefined): string {
  const trimmed = userId != null ? String(userId).trim() : ""
  return trimmed || "__anonymous__"
}

export function readExploreSession(
  userId?: string | null
): ExploreSessionSnapshot | null {
  if (!session) return null
  if (Date.now() - session.fetchedAt > DEFAULT_STALE_MS) {
    session = null
    return null
  }
  if (
    userId !== undefined &&
    exploreCacheUserKey(session.currentUserId) !== exploreCacheUserKey(userId)
  ) {
    return null
  }
  return session
}

export function writeExploreSession(snapshot: Omit<ExploreSessionSnapshot, "fetchedAt">) {
  session = { ...snapshot, fetchedAt: Date.now() }
}

export function patchExploreSession(
  patch: Partial<Omit<ExploreSessionSnapshot, "fetchedAt">>
) {
  if (!session) return
  session = { ...session, ...patch, fetchedAt: Date.now() }
}

export function getExploreTradesForView(
  view: ExploreTopView
): TradeForLeaderboard[] | null {
  const cached = readExploreSession()
  if (!cached?.tradesByView[view]) return null
  return cached.tradesByView[view] ?? null
}

export function setExploreTradesForView(
  view: ExploreTopView,
  trades: TradeForLeaderboard[]
) {
  if (!session) {
    session = {
      currentUserId: null,
      profiles: [],
      followingIds: [],
      requestedIds: [],
      followsYouIds: [],
      tradesByView: { [view]: trades },
      topView: view,
      scrollY: 0,
      fetchedAt: Date.now(),
    }
    return
  }
  session = {
    ...session,
    tradesByView: { ...session.tradesByView, [view]: trades },
    fetchedAt: Date.now(),
  }
}

export function invalidateExploreSession() {
  session = null
}
